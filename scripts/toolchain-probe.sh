#!/usr/bin/env bash
# toolchain-probe.sh —— 工具链版本与「潜伏告警」探针（只读 / 非阻断）
#
# 目的：把「工具链将来会怎么变红」提前看见——
#   工具链升级后**默认开启**的新告警会直接砸红门禁；而默认**关闭**的告警
#   平时完全看不见。本脚本做三件事（全部只读、零网络）：
#   ① 打印 `moon version`，并与 `setup-moonbit.sh` 的期望版本对照（漂移即提示）；
#   ② 用 `moon check --warn-list +a` 暴露**当前全部**告警（含默认关闭）；
#   ③ 打印包级依赖图（`moon tree --package`），佐证依赖面。
#
# 纪律：「发现告警」**永不**导致非零退出（只提示）；
#   仅当工具链不可用等**工具级错误**才非零退出。
# 用法: bash scripts/toolchain-probe.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.moon/bin:$PATH"

if ! command -v moon >/dev/null 2>&1; then
  echo "❌ 未找到 moon（export PATH=\"\$HOME/.moon/bin:\$PATH\" 或 bash scripts/setup-moonbit.sh）" >&2
  exit 1
fi

echo "=== 工具链探针（只读 / 非阻断）==="
echo "--- ① 版本 ---"
moon version | head -1 | sed 's/^/    /'
expected="$(grep -oE 'MOON_EXPECTED_VERSION:-[0-9.]+' scripts/setup-moonbit.sh | head -1 | sed 's/.*:-//')"
actual="$(moon version | head -1 | awk '{print $2}')"
if [[ -n "$expected" ]]; then
  if [[ "$actual" == "$expected" ]]; then
    echo "    ✅ 与 setup-moonbit.sh 期望版本一致（$expected）"
  else
    echo "    ⚠️ 与期望版本 $expected 不一致（实际 $actual）" >&2
  fi
fi

echo "--- ② 全部告警（含默认关闭；只提示不阻断）---"
moon check --warn-list +a 2>&1 | grep -E 'Warning|warn|^Error' | head -40 | sed 's/^/    /' || echo "    （无告警输出）"

echo "--- ③ 依赖图 ---"
moon tree --package 2>&1 | head -40 | sed 's/^/    /' || echo "    （moon tree 不可用）"

echo ">> 探针结束（非阻断）。"
