#!/usr/bin/env bash
# 格式门禁：moon fmt 会格式化 moon.mod / moon.pkg / 所有 .mbt，
# 提前拦截配置与代码格式腐化。
#
# 用法: bash scripts/fmt-check.sh
set -euo pipefail
export PATH="$HOME/.moon/bin:$PATH"

moon fmt --check
