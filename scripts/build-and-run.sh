#!/usr/bin/env bash
# 后端回归构建与运行（仅 wasm-gc —— 本仓库保留的唯一后端）。
#
# 说明：模块根不设包（core 式布局），构建需显式指定包名：lib（库）+ cmd/main（CLI）。
# 注意：不要加 native 阶段 —— 需系统 C 编译器，当前镜像未安装。
#
# 用法: bash scripts/build-and-run.sh
set -euo pipefail
export PATH="$HOME/.moon/bin:$PATH"

for t in wasm-gc; do
  echo "=== target: $t ==="
  moon build lib --target "$t" --release
  moon build cmd/main --target "$t" --release
  moon run cmd/main --target "$t"
  moon test --target "$t"
done
