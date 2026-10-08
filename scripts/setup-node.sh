#!/usr/bin/env bash
# setup-node.sh —— 校验 Node 运行时可用的版本，并安装 bench 的 JS 侧依赖。
#
# 【为什么需要它】bench 的计时器（唯一）与 JS 侧对照（base64-js / js-base64）、
# 以及 node Buffer 参照系，全部跑在 Node 上（bench/README.md 口径 ②）。
# 缺 Node，`run.mjs` 一步都走不了。
#
# 【版本策略】Node 由**系统镜像 / 平台**提供（本仓不代装运行时）；
# 本脚本只做两件事：
#   ① 断言 `node` 存在且版本 ≥ 期望下界（默认 20），否则显式失败；
#   ② 在 `bench/js/` 下跑 `npm install`（版本由 package.json **钉死**）。
#
# 用法:
#   bash scripts/setup-node.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

NODE_MIN_MAJOR="${NODE_MIN_MAJOR:-20}"

echo "=== 校验 Node 运行时（bench 计时器 + JS 侧对照）==="

if ! command -v node >/dev/null 2>&1; then
  echo "❌ 未找到 node。请先安装 Node ≥ ${NODE_MIN_MAJOR}（本仓不代装运行时）。" >&2
  exit 1
fi

major="$(node -p 'process.versions.node.split(".")[0]')"
echo ">> node $(node -v)"
if (( major < NODE_MIN_MAJOR )); then
  echo "❌ Node 版本过低：需要 ≥ ${NODE_MIN_MAJOR}，实际 $(node -v)" >&2
  exit 1
fi

echo ">> 安装 bench/js 依赖（base64-js / js-base64，版本由 package.json 钉死）"
(cd "$ROOT/bench/js" && npm install --no-audit --no-fund)

echo
echo ">> ✅ 完成。"
