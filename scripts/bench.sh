#!/usr/bin/env bash
# bench.sh —— 外部对照基准（本库 vs Rust base64 / JS base64 / node Buffer / MoonBit core）
#
# 【为什么是独立脚本，而不是 `gates.sh` 的一个阶段】
#   bench 需要 Node + rustup + cargo + npm，且跑一次是**分钟级**（cargo 编译 + 41 轮 × 4 尺寸）。
#   把它挂进门禁会让「改一行注释」也付出分钟级代价。故：
#     · **不进 `gates.sh` 默认阶段**；
#     · 走「按需 / 发布前」手动执行；
#     · 真要挂，也只能挂成可独立跳过的阶段（见 [S10 §6.2] 优先级 B 的取舍）。
#
# 【它固化的是什么】本仓三次性能翻车（S6 的 27%、S7 的 0.78×、S9 的误读）
#   **全部**是口径问题：选错对照层、拿单次直测当倍数、报告不带平台限定。
#   本脚本把这个「口径」从「每次手写探针时的心智负担」变成「脚本里的五条纪律」：
#     ① 数据在被测侧生成（不比数据搬运）
#     ② 计时器唯一（Node hrtime.bigint；各侧只做纯计算）
#     ③ 交错 A/B + 中位数 + min/p50/max 三值
#     ④ 防 DCE（结果回传 / 被读）
#     ⑤ 报告必带尺寸 + 平台限定
#     ⑥ 报告各方的 **SIMD 启用状态**（可验证：解析产物数 0xFD；不靠读 Cargo.toml）
#   详见 bench/README.md。
#
# 用法:
#   bash scripts/bench.sh                # 全量：校验 + 计时 + 体积
#   bash scripts/bench.sh --verify-only  # 只校验跨实现一致性（快，秒级）
#   SKIP_RUST=1 bash scripts/bench.sh    # 跳过 Rust 侧（无 rustup 时）
#   SKIP_SIZE=1 bash scripts/bench.sh    # 跳过体积段
#
# 退出码：0 = 全绿；1 = 跨实现校验失败（各家不在算同一件事）；2 = 工具链缺失。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.moon/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"

VERIFY_ONLY=0
for a in "$@"; do [[ "$a" == "--verify-only" ]] && VERIFY_ONLY=1; done

fail() { echo "❌ $*" >&2; exit 2; }
have() { command -v "$1" >/dev/null 2>&1; }

echo "=== 外部对照基准 bench.sh ==="
echo "    仓库: $ROOT"
echo

# ── 前置检查：缺工具**明说**，不静默降级 ────────────────────────────────────
have moon || fail "未找到 moon（bash scripts/setup-moonbit.sh 或 export PATH=\"\$HOME/.moon/bin:\$PATH\"）"
have node || fail "未找到 node（bench 的计时器与 JS 侧对照都需要它；见 scripts/setup-node.sh）"

# 运行时不齐时指向**一键配置**脚本（setup-bench-runtimes.sh = MoonBit + Rust + Node）：
# 缺 Rust 不致命（跳过即少一行），缺 MoonBit/Node 才致命（已在上两行拦下）。

RUST_OK=1
if [[ "${SKIP_RUST:-0}" == "1" ]]; then
  echo ">> SKIP_RUST=1 ⇒ 跳过 Rust 侧对照（表格中将缺 rust-base64 一行）"
  RUST_OK=0
elif have cargo && have rustc; then
  rustc --version | sed 's/^/    /'
else
  echo ">> ⚠️ 未找到 cargo/rustc ⇒ 跳过 Rust 侧。装上后本行数字才会出现：" >&2
  echo "     bash scripts/setup-rust.sh   （或一键：bash scripts/setup-bench-runtimes.sh）" >&2
  RUST_OK=0
fi
node -v | sed 's/^/    node /'
moon version | head -1 | sed 's/^/    /'
echo

# ── ① 构建 MoonBit 侧（harness + 体积探针）────────────────────────────────
echo ">> ① 构建 MoonBit harness 与体积探针（wasm-gc，--release）"
(cd bench && moon build moonbit/cmd/harness --target wasm-gc --release)
if (( ! VERIFY_ONLY )) && [[ "${SKIP_SIZE:-0}" != "1" ]]; then
  (cd bench && moon build size/cmd/empty --target wasm-gc --release)
  (cd bench && moon build size/cmd/uselib --target wasm-gc --release)
  (cd bench && moon build size/cmd/usecore --target wasm-gc --release)
fi

# ── ② 构建 Rust 侧（钉 =0.23.1；wasm32-unknown-unknown）───────────────────
if (( RUST_OK )); then
  echo ">> ② 构建 Rust 侧（base64 =0.23.1 → wasm32-unknown-unknown）"
  (cd bench/rust && cargo build --release --target wasm32-unknown-unknown --quiet)
fi

# ── ③ 一致性校验 + 计时（Node 驱动，唯一计时器）────────────────────────────
echo ">> ③ Node 驱动：跨实现校验 + 往返计时"
if [[ ! -d bench/js/node_modules ]]; then
  echo "     bench/js/node_modules 缺失 ⇒ npm install（base64-js / js-base64 钉版本）"
  (cd bench/js && npm install --no-audit --no-fund --silent)
fi
if (( VERIFY_ONLY )); then
  node bench/run.mjs --verify-only
else
  node bench/run.mjs --json bench/results.json
fi

# ── ③.5 SIMD 启用状态（口径 ⑥：可验证，不靠对 Cargo.toml 的阅读）──────────
#   为什么单列一步：跨实现差距有「用了向量指令」与「没用向量」两种来源，
#   记混会把可攻差距说成结构性差距。本步解析各自 wasm 产物、数 0xFD 指令。
echo
echo ">> ③.5 SIMD 启用状态（解析 wasm 产物，判据 = 有无 0xFD 指令）"
node bench/simd-probe.mjs

# ── ④ 体积（同一把尺子：raw + gzip -9，增量口径）──────────────────────────
if (( ! VERIFY_ONLY )) && [[ "${SKIP_SIZE:-0}" != "1" ]]; then
  echo
  echo ">> ④ 体积（增量口径：相对空 wasm-gc exec）"
  node bench/report-size.mjs
fi

echo
echo ">> ✅ bench 完成。"
(( VERIFY_ONLY )) || echo "   逐实现原文结果：bench/results.json（构建产物，不入库）"
