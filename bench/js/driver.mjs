// 唯一的计时器 —— 所有实现的数字都由本文件测出（bench/README.md 口径 ②）。
//
// 【为什么计时器必须唯一】各家自带的 bench 框架计时精度 / 口径不同
// （循环展开、JIT 预热、是否有 `process.hrtime` 之外的时钟），
// 跨实现对比若各用各的，比的是「谁的报告方式更宽松」。
// 本文件是唯一的 `hrtime.bigint` 使用者，各实现只做纯计算。
//
// 【交错 A/B（口径 ③）】每一轮对**所有**实现各测一遍，再取各实现的 41 轮中位数。
// 不交错就会把「前 10 秒机器凉、后 10 秒机器热」记成实现差异——
// [S7] 的 0.78× 正是这么来的。交错让漂移均摊到所有实现上，而不是流向某一个。

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { IMPLS, detBytes, checksum } from "./impls.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const BENCH_ROOT = resolve(HERE, "..");

/** 读 cases.json；缺省字段在此给默认值，避免 driver 里散落魔法数。 */
export function loadCases() {
  return JSON.parse(readFileSync(resolve(BENCH_ROOT, "cases.json"), "utf8"));
}

/**
 * 加载 MoonBit harness 导出（`wasm-gc`，Node 直接编译）。
 *
 * `imports: {}` 能成立，是因为 harness **不用 `println`**——`spectest.print_char`
 * 只在有打印时才是必需导入。这条是刻意的：少一个宿主导入 = 少一处两侧不一致。
 */
export async function loadMoonBit(wasmPath) {
  const bytes = readFileSync(wasmPath);
  const inst = await WebAssembly.instantiate(await WebAssembly.compile(bytes), {});
  return { name: "base64-moon", kind: "wasm-gc", exports: inst.exports };
}

/** 加载 Rust 侧 wasm（`wasm32-unknown-unknown`，无宿主导入）。 */
export async function loadRust(wasmPath) {
  const bytes = readFileSync(wasmPath);
  const inst = await WebAssembly.instantiate(await WebAssembly.compile(bytes), {});
  return { name: "rust-base64", kind: "wasm32", exports: inst.exports };
}

/** 计时闭包 `fn()` 一次，返回**毫秒**。 */
function timeOnce(fn) {
  const t0 = process.hrtime.bigint();
  const r = fn();
  const t1 = process.hrtime.bigint();
  return { ms: Number(t1 - t0) / 1e6, r };
}

/** 升序数组的某分位（最近邻，样本量小，不做插值）。 */
function quantile(sorted, q) {
  const idx = Math.min(sorted.length - 1, Math.max(0, Math.round(q * (sorted.length - 1))));
  return sorted[idx];
}

/**
 * 测一个「每轮调 `reps` 次」的被测对象：交错 A/B + 中位数 + min/p50/max。
 *
 * @param {() => number} fn 单次调用（返回值会被累加，防 DCE）
 * @returns {{min:number, p50:number, max:number}} 单次调用耗时（ms）
 */
export function measure(fn, { rounds, reps, warmup }) {
  // 预热：让 JIT / GC 先进入稳态；不预热的第一轮会污染 max。
  for (let i = 0; i < warmup; i++) fn();
  const perCall = [];
  let sink = 0;
  for (let r = 0; r < rounds; r++) {
    const { ms, r: v } = timeOnce(() => {
      for (let k = 0; k < reps; k++) sink += fn();
      return sink;
    });
    perCall.push(ms / reps);
  }
  // 防 DCE（口径 ④）：sink 必须被**读**，否则整段可被消除。
  if (sink === 0x7fffffff) console.error("sink", sink);
  perCall.sort((a, b) => a - b);
  return { min: perCall[0], p50: quantile(perCall, 0.5), max: perCall[perCall.length - 1] };
}

/**
 * 交错 A/B：同一轮里依次测每个 subject，共 `rounds` 轮，各自取中位数。
 *
 * `subjects` = `[{ name, kind, run(reps) -> number }]`
 */
export function interleaved(subs, { rounds, reps, warmup }) {
  for (const s of subs) for (let i = 0; i < warmup; i++) s.run(1);
  const samples = new Map(subs.map((s) => [s.name, []]));
  let sink = 0;
  for (let r = 0; r < rounds; r++) {
    for (const s of subs) {
      const t0 = process.hrtime.bigint();
      for (let k = 0; k < reps; k++) sink += s.run(1);
      const t1 = process.hrtime.bigint();
      samples.get(s.name).push(Number(t1 - t0) / 1e6 / reps);
    }
  }
  if (sink === 0x7fffffff) console.error("sink", sink);
  const out = {};
  for (const [name, arr] of samples) {
    const sorted = [...arr].sort((a, b) => a - b);
    out[name] = { min: sorted[0], p50: quantile(sorted, 0.5), max: sorted[sorted.length - 1] };
  }
  return out;
}

export { quantile };
