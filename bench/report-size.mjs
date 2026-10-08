// 体积报告 —— **同一把尺子**量全部实现（raw + gzip -9，增量口径）。
//
// 【为什么单独一个入口，而不是塞进 run.mjs】
//   run.mjs 的产物全部来自「Node 能加载的 wasm」；而体积段要读的是**文件体积**，
//   包括 Rust 的 cdylib 与 JS 的源码。两者数据来源不同、可比性等级不同
//   （见下表的「备注」列），混在一个函数里会把「同一把尺子」悄悄变成两把。
//
// 【可比性纪律】表按**实现归属**分组打印，组间**不做倍数比较**：
//   · MoonBit 组（本库 vs core）—— 同运行时，**最干净**的一格，可比；
//   · Rust 组 —— 不同运行时（没有 GC），只作参照；
//   · JS 组 —— 是源码不是产物，与 wasm 体积**不同口径**，只作参照。

import { readFileSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
const B = resolve(HERE, "_build/wasm-gc/release/build");

function sz(path) {
  const bytes = readFileSync(path);
  return { raw: bytes.length, gzip: gzipSync(bytes, { level: 9 }).length };
}

const base = sz(resolve(B, "TryAndRun-TvT/base64-moon-size/cmd/empty/empty.wasm"));

const rows = [
  {
    group: "MoonBit（同运行时，可比）",
    label: "空 exec（基线）",
    ...base,
    delta: 0,
  },
  {
    group: "MoonBit（同运行时，可比）",
    label: "base64-moon（本库）",
    ...sz(resolve(B, "TryAndRun-TvT/base64-moon-size/cmd/uselib/uselib.wasm")),
  },
  {
    group: "MoonBit（同运行时，可比）",
    label: "core（官方）",
    ...sz(resolve(B, "TryAndRun-TvT/base64-moon-size/cmd/usecore/usecore.wasm")),
  },
  {
    group: "Rust（不同运行时，仅参照）",
    label: "rust-base64 cdylib",
    ...sz(resolve(HERE, "rust/target/wasm32-unknown-unknown/release/base64_bench_rust.wasm")),
  },
  {
    group: "JS（源码口径，不同量纲，仅参照）",
    label: "base64-js（源码）",
    ...sz(resolve(HERE, "js/node_modules/base64-js/index.js")),
  },
  {
    group: "JS（源码口径，不同量纲，仅参照）",
    label: "js-base64（源码）",
    ...sz(resolve(HERE, "js/node_modules/js-base64/base64.mjs")),
  },
];

for (const r of rows) r.delta ??= r.raw - base.raw;

const fmt = (n) => String(n).padStart(7);
console.log(
  "  分组".padEnd(30) + "实现".padEnd(22) + "raw".padStart(8) + "gzip".padStart(8) + "增量".padStart(9),
);
let last = "";
for (const r of rows) {
  const g = r.group === last ? "" : r.group;
  last = r.group;
  console.log(
    "  " + g.padEnd(28) + r.label.padEnd(22) + fmt(r.raw) + fmt(r.gzip) + fmt(r.delta),
  );
}
console.log(`
  · 增量 = raw − 空 exec（${base.raw} B）；基线那行增量恒为 0。
  · gzip -9 会把 <200 B 的文件压得**略大**（gzip 头开销），故基线行 gzip > raw 属正常。
  · 组间不可比：Rust 没有 GC 运行时，JS 报的是源码而非产物。
  · 同组内：本库增量 ${rows[1].raw - base.raw} B vs core ${rows[2].raw - base.raw} B。`);
