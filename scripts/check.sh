#!/usr/bin/env bash
# 静态检查门禁：--deny-warn 把告警（如 unused_package）升级为失败。
#
# 用法: bash scripts/check.sh
set -euo pipefail
export PATH="$HOME/.moon/bin:$PATH"

moon check --deny-warn
