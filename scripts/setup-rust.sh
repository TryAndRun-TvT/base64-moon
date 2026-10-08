#!/usr/bin/env bash
# setup-rust.sh —— 安装 Rust 工具链并加 wasm32 目标（bench 的 Rust 侧对照用）。
#
# 【为什么需要它】bench 的 rust-base64 对照要把 Rust 编到
# `wasm32-unknown-unknown`（不是 native），才能与 wasm-gc 侧**同执行模型、同时计器**
# 比较（bench/README.md 口径 ②）。缺这一步，表格里就永远缺 rust-base64 那一行。
#
# 【版本策略】与 MoonBit 侧同款取舍：官方 `rustup` 只按 channel 安装，
# 故本脚本「装 stable + **装后断言实际版本**」：
#   · 期望版本 = `RUST_EXPECTED_VERSION`（默认见下），升级时刻意更新；
#   · 不匹配**默认仅告警**；需要强复现设 `RUST_STRICT_VERSION=1` ⇒ 非零退出。
#
# 【无 root 也适用】rustup 默认装到 `$HOME/.cargo`、`$HOME/.rustup`，
# 不写系统目录。装完**当前 shell 需要** `export PATH="$HOME/.cargo/bin:$PATH"`。
#
# 用法:
#   bash scripts/setup-rust.sh              # 装 stable + wasm32-unknown-unknown
#   RUST_STRICT_VERSION=1 bash scripts/setup-rust.sh
set -euo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

RUST_EXPECTED_VERSION="${RUST_EXPECTED_VERSION:-1.99.0}"
TARGET="wasm32-unknown-unknown"

echo "=== 安装 Rust 工具链（bench Rust 侧对照）==="

if command -v rustup >/dev/null 2>&1; then
  echo ">> rustup 已存在，跳过安装"
else
  echo ">> 下载并安装 rustup（stable, minimal profile, 含 $TARGET 目标）"
  curl -fsSL https://sh.rustup.rs -o /tmp/rustup-init.sh
  sh /tmp/rustup-init.sh -y --default-toolchain stable --profile minimal --target "$TARGET"
fi

# ── 装后断言：目标是否齐 + 版本是否漂 ─────────────────────────────────────────
if ! rustup target list --installed | grep -qx "$TARGET"; then
  echo ">> 补装目标 $TARGET"
  rustup target add "$TARGET"
fi

actual="$(rustc --version | awk '{print $2}')"
echo ">> rustc $actual（目标 $TARGET 已装）"

if [[ "$actual" == "$RUST_EXPECTED_VERSION" ]]; then
  echo ">>> ✅ Rust 版本与期望一致：$actual"
else
  echo ">>> ⚠️ Rust 版本漂移：实际 $actual ≠ 期望 $RUST_EXPECTED_VERSION" >&2
  echo "    处置：确认 bench/rust 的对照数字是否需要重跑（版本变更会静默改变被测量），" >&2
  echo "          再决定是否更新 RUST_EXPECTED_VERSION（本仓未钉版）。" >&2
  if [[ "${RUST_STRICT_VERSION:-0}" == "1" ]]; then
    echo ">>> RUST_STRICT_VERSION=1 ⇒ 版本漂移视为失败。" >&2
    exit 1
  fi
fi

echo
echo ">> ✅ 完成。当前 shell 请执行：export PATH=\"\$HOME/.cargo/bin:\$PATH\""
