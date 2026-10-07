#!/usr/bin/env bash
# gates.sh —— 本地一键全量门禁（push 流水线未启用时的等价替代）
#
# 背景：本项目暂不启用 push 流水线（每次推送重复全量构建+测试，资源收益不成比例）。
#   门禁**不因不启用而失效**——各阶段命令抽离在 `scripts/` 下，本脚本把它们串成一条链，
#   供**本地/提交前/发布前**一键执行。
#
# 默认阶段（顺序即依赖顺序，任一红即整链红）：
#   fmt-check → check → test → docs-link-check → docs-ref-check → docs-index → test-scale → build-and-run
#
# 用法:
#   bash scripts/gates.sh                       # 全量
#   STAGES="check test" bash scripts/gates.sh    # 只跑指定阶段（空格分隔）
#   SKIP_SLOW=1 bash scripts/gates.sh            # 跳过耗时阶段（build-and-run）
#   KEEP_GOING=1 bash scripts/gates.sh           # 失败不中断，跑完再汇总
#
# 退出码：0 = 全绿；1 = 至少一个阶段红；2 = 阶段脚本不存在（拼错阶段名）。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.moon/bin:$PATH"

DEFAULT_STAGES="fmt-check check test docs-link-check docs-ref-check docs-index test-scale build-and-run"
SLOW_STAGES="build-and-run"

STAGES="${STAGES:-$DEFAULT_STAGES}"
if [[ "${SKIP_SLOW:-0}" == "1" ]]; then
  filtered=""
  for s in $STAGES; do
    skip=0
    for slow in $SLOW_STAGES; do [[ "$s" == "$slow" ]] && skip=1; done
    (( skip )) || filtered+="$s "
  done
  STAGES="${filtered% }"
fi

fail=0
passed=""
failed=""
echo "=== 本地全量门禁 gates.sh ==="
echo "    阶段: $STAGES"
echo

for stage in $STAGES; do
  script="scripts/$stage.sh"
  if [[ ! -f "$script" ]]; then
    echo "!! 阶段脚本不存在: $script（可选阶段: $DEFAULT_STAGES）" >&2
    exit 2
  fi
  log="/tmp/gates-$stage.log"
  start="$(date +%s)"
  printf '[%s] ... ' "$stage"
  if bash "$script" >"$log" 2>&1; then
    printf '✅ (%.0fs, 日志 %s)\n' "$(($(date +%s) - start))" "$log"
    passed+="$stage "
  else
    printf '❌ (%.0fs, 日志 %s)\n' "$(($(date +%s) - start))" "$log"
    tail -8 "$log" | sed 's/^/       /'
    failed+="$stage "
    fail=1
    if [[ "${KEEP_GOING:-0}" != "1" ]]; then
      echo
      echo ">> 门禁链在 '$stage' 处中断（设 KEEP_GOING=1 可跑完全部阶段）。"
      exit 1
    fi
  fi
done

echo
if (( fail )); then
  echo ">> 门禁未通过 ❌ —— 失败阶段: ${failed% }　通过阶段: ${passed% }"
  exit 1
fi
echo ">> 门禁全绿 ✅ —— 通过阶段: ${passed% }"
echo "   注：push CI 未启用，本链是提交/发布前**唯一**的自动质量闸门（AGENTS.md §二.4）。"
