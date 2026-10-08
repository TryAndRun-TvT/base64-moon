#!/usr/bin/env bash
# bench-simd-probe-check.sh —— SIMD 探针的**负向验证**（AGENTS.md §三.2 铁律 5）。
#
# 【为什么需要】`bench/simd-probe.mjs` 是「平台税里有没有 SIMD 成分」这条结论的**唯一证据源**。
#   一个只会打印「无」的探针会让结论永远成立——那不算证据。故必须先证明它**能红**：
#   喂「确有向量指令」的产物时必须报「有」，喂「纯标量」时必须报「无」。
#
# 【判据】用一对**确定的**产物做真值：
#   · 有 SIMD：本机现编一个显式 @v128 的 wasm-gc 探针（8 条 0xFD，S1 §5.1 的可复现版）；
#   · 无 SIMD：默认可执行产物（或 bench 的 Rust 默认产物）。
#   两者判定必须相反；否则探针失效。
#
# 用法: bash scripts/bench-simd-probe-check.sh
# 退出码: 0 = 探针可红（有/无都判对）；1 = 探针失效；2 = 前置缺失。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.moon/bin:$PATH"

command -v node >/dev/null 2>&1 || { echo "❌ 未找到 node" >&2; exit 2; }

echo "=== SIMD 探针负向验证 ==="
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── 造一个「确定有 SIMD」的 wasm-gc 产物：显式调用 @v128 ────────────────────
mkdir -p "$TMP/probe/cmd/p"
cat > "$TMP/probe/moon.mod" <<'MOD'
name = "probe/v128-check"
version = "0.0.1"
preferred_target = "wasm-gc"
MOD
cat > "$TMP/probe/cmd/p/moon.pkg" <<'PKG'
import {
  "moonbitlang/core/v128" @v128,
}
pkgtype(kind: "executable")
warnings = "-14"
PKG
cat > "$TMP/probe/cmd/p/main.mbt" <<'MBT'
fn main {
  let a : V128 = @v128.i64x2_const(1UL, 2UL)
  let b : V128 = @v128.i64x2_splat(3UL)
  let c = @v128.v128_and_(a, b)
  let d = @v128.v128_xor(c, a)
  let e = @v128.i8x16_swizzle(d, a)
  let r : UInt64 = @v128.i64x2_extract_lane(e, 0)
  println(r)
}
MBT
(cd "$TMP/probe" && moon build cmd/p --target wasm-gc --release >/dev/null 2>&1)
BUILT="$TMP/probe/_build/wasm-gc/release/build/cmd/p/p.wasm"
[[ -f "$BUILT" ]] || { echo "❌ 无法构造「有 SIMD」的对照产物（moon 构建失败）" >&2; exit 2; }
# 必须先**拷出来**：两次构建共用一个输出路径，第二次会覆盖第一次。
HAVE_SIMD="$TMP/have_simd.wasm"
cp "$BUILT" "$HAVE_SIMD"

# 造一个「确定无 SIMD」的产物：同一工程改成纯标量
cat > "$TMP/probe/cmd/p/main.mbt" <<'MBT'
fn main {
  let mut acc : UInt64 = 0UL
  let mut i = 0
  while i < 64 { acc = acc + i.to_uint64(); i = i + 1 }
  println(acc)
}
MBT
(cd "$TMP/probe" && moon build cmd/p --target wasm-gc --release >/dev/null 2>&1)
NO_SIMD="$TMP/none_simd.wasm"
cp "$BUILT" "$NO_SIMD"

# ── 跑探针，断言两者的判定相反 ──────────────────────────────────────────────
out_have="$(node bench/simd-probe.mjs "$HAVE_SIMD" 2>&1)"
out_none="$(node bench/simd-probe.mjs "$NO_SIMD" 2>&1)"

echo "$out_have" | grep -q "判定：有" || { echo "❌ 探针在「有 SIMD」的产物上报了「无」——探针失效" >&2; echo "$out_have" >&2; exit 1; }
echo "$out_none" | grep -q "判定：无" || { echo "❌ 探针在「无 SIMD」的产物上报了「有」——探针失效" >&2; echo "$out_none" >&2; exit 1; }

rh="$(echo "$out_have" | grep -oE '有（[0-9]+ 条' | grep -oE '[0-9]+')"
echo "  ✅ 显式 @v128 产物 → 有（${rh} 条 SIMD 指令）"
echo "  ✅ 纯标量产物     → 无（0 条）"
echo ">> 探针可红：有/无都能判对。结论「外部对照在 wasm 上是标量」因此是**可验证**的。"
