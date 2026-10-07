#!/usr/bin/env bash
# test-scale.sh —— 测试规模护栏
#
# 目的：把「测试资产会被无限膨胀」这件事变成可执行门禁，防止：
#   ① 单测试文件无上限增长（>LIMIT 行即失败）；
#   ② 机械展开式用例（行数涨、真值点数不涨）。
#
# 用法: bash scripts/test-scale.sh
# 环境变量: TEST_FILE_LIMIT（默认 800）
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
LIMIT="${TEST_FILE_LIMIT:-800}"

echo "=== 测试规模护栏（单测试文件 ≤${LIMIT} 行）==="
fail=0
total=0
while IFS= read -r f; do
  n="$(wc -l <"$f")"
  total=$((total + n))
  if (( n > LIMIT )); then
    printf '  ❌ %-52s %5d 行（超限 %d）\n' "$f" "$n" "$((n - LIMIT))"
    fail=1
  else
    printf '  ✅ %-52s %5d 行\n' "$f" "$n"
  fi
done < <(find lib cmd -name '*_test.mbt' -o -name '*_wbtest.mbt' 2>/dev/null | sort)

echo "  ---- 合计 $total 行"
if (( fail )); then
  echo
  echo ">> 存在超限测试文件：请按『一个包一个测试主题』拆分（见 AGENTS.md）。"
  exit 1
fi
echo ">> 全部测试文件在限内。"
