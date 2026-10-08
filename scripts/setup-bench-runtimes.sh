#!/usr/bin/env bash
# setup-bench-runtimes.sh —— 一键备齐 bench 的**全部运行时**（MoonBit / Rust / Node）。
#
# 【为什么需要它】`scripts/bench.sh` 跨三种运行时：MoonBit（本库 + core 对照）、
# Rust（rust-base64 对照）、Node（计时器 + JS 侧对照 + node Buffer 参照）。
# 此前三者的安装散落在三处、且只文档化、不脚本化——换台机器就要重踩一遍。
# 本脚本把「环境配置」也变成可复跑的一步，与 bench/README.md 的口径纪律配套。
#
# 【它做什么】
#   ① MoonBit：`setup-moonbit.sh`（装 latest 通道 + 断言期望版本）；
#   ② Rust：`setup-rust.sh`（装 stable + wasm32-unknown-unknown）；
#   ③ Node：`setup-node.sh`（断言版本下界 + 装 bench/js 依赖）。
#
# 【它不做什么】不代装系统运行时（Node 由镜像/平台提供）；不写任何凭据。
#
# 用法:
#   bash scripts/setup-bench-runtimes.sh              # 全部
#   SKIP_RUST=1 bash scripts/setup-bench-runtimes.sh # 只装 MoonBit + Node
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== bench 运行时一键配置（MoonBit / Rust / Node）==="
echo

echo "── ① MoonBit ────────────────────────────────────────────"
bash "$SCRIPT_DIR/setup-moonbit.sh"

echo
if [[ "${SKIP_RUST:-0}" == "1" ]]; then
  echo "── ② Rust：SKIP_RUST=1 ⇒ 跳过（表格中将缺 rust-base64 一行）────────"
else
  echo "── ② Rust ───────────────────────────────────────────────"
  bash "$SCRIPT_DIR/setup-rust.sh"
fi

echo
echo "── ③ Node ───────────────────────────────────────────────"
bash "$SCRIPT_DIR/setup-node.sh"

echo
echo "=== ✅ 全部运行时就绪。下一步：bash scripts/bench.sh ==="
echo "    提示：Rust 装在 \$HOME/.cargo，当前 shell 需 export PATH=\"\$HOME/.cargo/bin:\$PATH\"。"
