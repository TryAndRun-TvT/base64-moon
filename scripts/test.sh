#!/usr/bin/env bash
# 全项目单元测试。
#
# 用法: bash scripts/test.sh
set -euo pipefail
export PATH="$HOME/.moon/bin:$PATH"

moon test
