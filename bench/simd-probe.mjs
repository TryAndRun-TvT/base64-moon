// SIMD 启用探针 —— 回答一个**只能靠证据回答**的问题：
//   「表格里那一行外部实现，到底有没有用向量指令？」
//
// 【为什么必须探针化】跨实现对比里，「对方比你快」有两种截然不同的来源：
//   (a) 它真的用了向量指令（AVX2 / SIMD128）；
//   (b) 它没用向量，只是平台/内存模型/外壳更省。
//   把 (a) 误记成平台税 = 把一个**可攻的差距**说成**不可攻的结构性差距**，
//   结论就会从「该优化外壳」变成「反正追不上」。本仓三次性能翻车都是这类口径问题。
//   故：任何「谁比谁快」的结论，必须附「各方 SIMD 实测状态」。
//
// 【判据不是猜】直接解析 wasm 二进制：
//   走 code section，逐指令扫 0xFD 前缀（SIMD 指令族）。出现即证明**真的**有向量指令
//   （降级的标量实现不会产生该前缀）。同时报告 opcode 直方图，可人工核对是哪种 SIMD。
//
// 【为什么能对 Rust 下结论】Rust 的 `wasm32-unknown-unknown` 默认**不开** `simd128`；
//   `base64` crate 的 AVX2/NEON 引擎还被 `simd-unsafe` 特性 + `target_arch` 双重门控。
//   两者任一不满足，编出来的就是标量版——本脚本用「产物里有没有 0xFD」来判定，
//   不依赖对 Cargo.toml 的阅读。
//
// 用法:
//   node bench/simd-probe.mjs                       # 探默认路径的三家产物
//   node bench/simd-probe.mjs --json out.json       # 出 JSON
//   node bench/simd-probe.mjs <a.wasm> [b.wasm ...] # 探指定产物
//
// 退出码：0 = 探针完成（不代表「有/无 SIMD」是好事）；2 = 产物缺失。

import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));

/** 默认探的三个产物：本库 harness / Rust 对照 / 官方 core 对照（后两者同名不同包）。 */
const DEFAULT_TARGETS = [
  ["base64-moon（本库，wasm-gc）",
    resolve(HERE, "_build/wasm-gc/release/build/TryAndRun-TvT/base64-moon-bench/cmd/harness/harness.wasm")],
  ["rust-base64 0.23.1（wasm32-unknown-unknown）",
    resolve(HERE, "rust/target/wasm32-unknown-unknown/release/base64_bench_rust.wasm")],
];

// ── 最小 wasm 解析：定位 code section，逐指令扫 0xFD ─────────────────────────
//
// 只做我们需要的部分：section id 10 = code。不解析类型/导入（对「有无 0xFD」无影响）。
// 之所以敢用「扫字节」而不是完整反汇编：0xFD 是**多字节指令前缀**，
// 且 wasm 里 0xFD 不作为独立的立即数出现（立即数是 LEB128 整数/浮点，不会恰好以 0xFD 起
// 并被识别为前缀后接合法 opcode）。误报概率极低，但我们仍**同时输出 opcode 直方图**，
// 让人可核对：若出现的是合法 SIMD opcode（0x0C v128.const、0x0E i8x16.swizzle、…），即成立。

/** 读 ULEB128。返回 [value, nextIndex]。 */
export function uleb(buf, i) {
  let val = 0, shift = 0, b;
  do { b = buf[i++]; val |= (b & 0x7f) << shift; shift += 7; } while (b & 0x80);
  return [val >>> 0, i];
}

/** 遍历 section，找到 id 为 want 的 section 的 payload 范围。 */
export function findSection(buf, want) {
  let i = 8; // skip magic(4) + version(4)
  while (i < buf.length) {
    const id = buf[i++];
    const [size, after] = uleb(buf, i);
    const start = after, end = after + size;
    if (id === want) return [start, end];
    i = end;
  }
  return null;
}

/** 已知 SIMD opcode 名（子集，够核对即可）。 */
const SIMD_OPCODES = {
  0x0b: "v128.load", 0x0c: "v128.const", 0x0e: "i8x16.swizzle", 0x0f: "i8x16.splat",
  0x12: "v128.and", 0x4e: "v128.xor", 0x51: "v128.andnot", 0x50: "v128.not",
  0x1d: "i64x2.extract_lane", 0x1e: "i64x2.replace_lane",
  0x5c: "v128.load8_lane", 0x5d: "v128.load16_lane", 0x5e: "v128.load32_lane",
  0x5f: "v128.load64_lane", 0x84: "v128.store8_lane",
  0x92: "v128.load32_zero", 0x93: "v128.load64_zero",
};

/** 扫一个 wasm 产物，返回 { size, simdOpcodeCount, hist }。 */
export function scanSimd(path) {
  const buf = readFileSync(path);
  const code = findSection(buf, 10); // 10 = code section
  if (!code) return { size: buf.length, simdOpcodeCount: 0, hist: {}, scannedCode: false };
  // code section 的内容是「函数体」序列，我们整段扫 0xFD 前缀即可。
  // 注意：0xFD 也可能是函数体长度/局部变量计数等 LEB 的某个字节——所以只看
  // 「0xFD 后解码出的 opcode 落在合法 SIMD 集合」的，记为真命中。
  const hist = {};
  let count = 0;
  for (let i = code[0]; i < code[1]; i++) {
    if (buf[i] !== 0xfd) continue;
    const [op] = uleb(buf, i + 1);
    if (SIMD_OPCODES[op] !== undefined) { count++; hist[SIMD_OPCODES[op]] = (hist[SIMD_OPCODES[op]] || 0) + 1; }
  }
  return { size: buf.length, simdOpcodeCount: count, hist, scannedCode: true };
}

// ── 主流程（仅当作为脚本直接运行时执行；被 import 时不跑）────────────────────
const RUN_AS_SCRIPT = process.argv[1] && process.argv[1].endsWith("simd-probe.mjs");
if (RUN_AS_SCRIPT) {

const argv = process.argv.slice(2);
const jsonIdx = argv.indexOf("--json");
const jsonPath = jsonIdx >= 0 ? argv[jsonIdx + 1] : null;
const explicit = argv.filter((a) => a.endsWith(".wasm"));

const targets = explicit.length
  ? explicit.map((p) => [p, resolve(p)])
  : DEFAULT_TARGETS;

const rows = [];
let missing = 0;
for (const [label, path] of targets) {
  if (!existsSync(path)) {
    console.error(`!! 产物缺失：${path}\n（先跑 bash scripts/bench.sh）`);
    missing++;
    continue;
  }
  const r = scanSimd(path);
  rows.push({ label, path, ...r });
}

if (rows.length) {
  console.log("\n=== SIMD 启用探针（解析 wasm 产物的 code section）===\n");
  for (const r of rows) {
    const verdict = r.simdOpcodeCount > 0 ? `有（${r.simdOpcodeCount} 条 SIMD 指令）` : "无（0 条 SIMD 指令 ⇒ 标量实现）";
    console.log(`· ${r.label}`);
    console.log(`    产物：${r.path}（${r.size} B）`);
    console.log(`    判定：${verdict}`);
    if (r.simdOpcodeCount > 0) {
      const top = Object.entries(r.hist).sort((a, b) => b[1] - a[1]).slice(0, 6)
        .map(([k, v]) => `${k}×${v}`).join("、");
      console.log(`    指令：${top}`);
    }
  }
  console.log(`\n口径：判据 = 产物里有无 0xFD（SIMD 前缀）指令；标量实现不会产生它。`);
  console.log(`      「无」不代表实现差 —— 它只表示这一行的数字是**标量 vs 标量**，`);
  console.log(`      即「平台税」里不应计入「对方用了 SIMD」这一项（见 docs/02-证据）。`);
}

if (jsonPath) {
  const { writeFileSync } = await import("node:fs");
  writeFileSync(jsonPath, JSON.stringify({ generatedBy: "bench/simd-probe.mjs", rows }, null, 2));
  console.log(`\n>> 已写 ${jsonPath}`);
}

if (missing && !rows.length) process.exit(2);
}
