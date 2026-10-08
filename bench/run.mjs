// bench 主程序 —— 加载全部实现、校验一致性、量往返、出表。
//
// 出口：
//   node bench/run.mjs                 # 全量：校验 + 计时 + 出 JSON
//   node bench/run.mjs --verify-only   # 只校验（快；负向验证用）
//   node bench/run.mjs --json <path>   # 把结果写到指定文件
//
// 退出码：0 = 全绿；1 = 校验失败（各家不在算同一件事）；2 = 实现缺失。

import { writeFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { IMPLS, detBytes, checksum } from "./js/impls.mjs";
import {
  loadCases,
  loadMoonBit,
  loadRust,
  interleaved,
} from "./js/driver.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const MOON_WASM = resolve(
  HERE,
  "_build/wasm-gc/release/build/TryAndRun-TvT/base64-moon-bench/cmd/harness/harness.wasm",
);
const RUST_WASM = resolve(
  HERE,
  "rust/target/wasm32-unknown-unknown/release/base64_bench_rust.wasm",
);

const args = process.argv.slice(2);
const verifyOnly = args.includes("--verify-only");
const jsonIdx = args.indexOf("--json");
const jsonPath = jsonIdx >= 0 ? args[jsonIdx + 1] : null;

function die(msg) {
  console.error(`\n!! ${msg}`);
  process.exit(2);
}

if (!existsSync(MOON_WASM)) die(`找不到 MoonBit 产物：${MOON_WASM}\n（先跑 bash scripts/bench.sh，或 moon build）`);
if (!existsSync(RUST_WASM)) die(`找不到 Rust 产物：${RUST_WASM}\n（先跑 bash scripts/bench.sh，或 cd bench/rust && cargo build --release --target wasm32-unknown-unknown）`);

const cases = loadCases();
const moon = await loadMoonBit(MOON_WASM);
const rust = await loadRust(RUST_WASM);

// ── 第一步：一致性校验（先证明各家在算同一件事，再谈快慢）──────────────────
//
// 这一步是框架的**承重墙**：没有它，后面所有数字都可能是「各自算了不同的东西」。
// 判据是跨实现校验和逐位相同（编码串 + 往返结果），不是「都跑通了」。

const mismatches = [];
const verifyRows = [];
/// 参与校验的实现名（JS 侧 + MoonBit 侧两家 + Rust）。
const VERIFIED_IMPLS = [
  "base64-moon",
  "moonbit-core",
  "rust-base64",
  ...IMPLS.map((i) => i.name),
];
for (const n of cases.verifySizes) {
  const s = cases.seed;
  const src = detBytes(n, s);
  // 编码串校验和：MoonBit / Rust 走 verify_encode；JS 走 encodeChecksum。
  const encChecks = [
    ["base64-moon", moon.exports.verify_encode(n, s)],
    ["moonbit-core", moon.exports.verify_core_encode(n, s)],
    ["rust-base64", rust.exports.verify_encode(n, s)],
    ...IMPLS.map((i) => [i.name, i.encodeChecksum(src)]),
  ];
  // 往返校验和：MoonBit / Rust 走 verify_roundtrip；JS 走 roundtrip 后重算。
  const rtChecks = [
    ["base64-moon", moon.exports.verify_roundtrip(n, s)],
    ["moonbit-core", moon.exports.verify_core_roundtrip(n, s)],
    ["rust-base64", rust.exports.verify_roundtrip(n, s)],
    ...IMPLS.map((i) => [i.name, checksum(i.roundtrip(src))]),
  ];
  const encBase = encChecks[0][1];
  const rtBase = rtChecks[0][1];
  for (const [name, v] of encChecks) {
    if (v !== encBase) mismatches.push(`n=${n} 编码串校验和：${name}=${v} ≠ base64-moon=${encBase}`);
  }
  for (const [name, v] of rtChecks) {
    if (v !== rtBase) mismatches.push(`n=${n} 往返校验和：${name}=${v} ≠ base64-moon=${rtBase}`);
  }
  if (moon.exports.verify_roundtrip(n, s) < 0) mismatches.push(`n=${n} MoonBit 往返自校验失败（-1）`);
  if (rust.exports.verify_roundtrip(n, s) < 0) mismatches.push(`n=${n} Rust 往返自校验失败（-1）`);
  verifyRows.push({ n, enc: encBase, rt: rtBase });
}

console.log("=== 一致性校验（跨实现校验和逐位对账）===");
console.log("  n".padEnd(10) + "编码串校验和".padEnd(16) + "往返校验和");
for (const r of verifyRows) {
  console.log(`  ${String(r.n).padEnd(8)}${String(r.enc).padEnd(16)}${r.rt}`);
}
if (mismatches.length) {
  console.error("\n!! 跨实现不一致 —— 数字无意义，先修这个：");
  for (const m of mismatches) console.error("   · " + m);
  process.exit(1);
}

// 实现总数动态算：加/减一家（比如 SKIP_RUST）时这行不会说谎。
// 家数动态取（加/减一家时这行不会说谎）。
console.log(`  ✅ ${cases.verifySizes.length} 个尺寸 × ${VERIFIED_IMPLS.length} 家实现，校验和全部一致\n`);

if (verifyOnly) process.exit(0);

// ── 第二步：往返计时（交错 A/B + 中位数 + min/p50/max）─────────────────────
//
// 统一被测量 = **往返**（encode + decode）：各侧都只导出往返，
// 故跨实现对比只在这个口径上做。内核段（slice）只在 MoonBit vs Rust 之间比，
// 因为 JS 侧没有「零分配内核」这个层次，比了就是不同层（[S7 §2.1] 要素 ①）。

const subjects = [
  {
    name: "base64-moon",
    kind: "wasm-gc",
    run: (reps) => moon.exports.bench_roundtrip(size, cases.seed, reps),
  },
  {
    name: "moonbit-core",
    kind: "wasm-gc",
    run: (reps) => moon.exports.bench_core_roundtrip(size, cases.seed, reps),
  },
  {
    name: "rust-base64",
    kind: "wasm32",
    run: (reps) => rust.exports.bench_roundtrip(size, cases.seed, reps),
  },
  ...IMPLS.map((impl) => ({
    name: impl.name,
    kind: impl.kind,
    run: (reps) => {
      let acc = 0;
      const src = detBytes(size, cases.seed);
      for (let k = 0; k < reps; k++) acc = (acc + checksum(impl.roundtrip(src))) | 0;
      return acc;
    },
  })),
];

const { rounds, warmup, reps: repsCfg, smallThreshold } = cases.timing;
const results = [];
let size = cases.sizes[0]; // 供闭包读，逐尺寸更新

console.log("=== 往返耗时（ms/次，交错 A/B，中位数）===");
console.log(
  "  实现".padEnd(16) + "n".padEnd(10) + "min".padEnd(12) + "p50".padEnd(12) + "max".padEnd(12) + "MB/s(p50)",
);
for (size of cases.sizes) {
  const reps = size <= smallThreshold ? repsCfg.small : repsCfg.large;
  const measured = interleaved(subjects, { rounds, reps, warmup });
  const base = measured["base64-moon"].p50;
  for (const s of subjects) {
    const m = measured[s.name];
    const mbs = (size / 1e6) / (m.p50 / 1e3) / 2; // 往返 = encode+decode，吞吐按单向计
    results.push({
      size,
      impl: s.name,
      kind: s.kind,
      min: m.min,
      p50: m.p50,
      max: m.max,
      ratioToMoon: m.p50 / base,
      mbpsOneWay: mbs,
    });
    console.log(
      `  ${s.name.padEnd(14)}${String(size).padEnd(10)}${m.min.toFixed(5).padEnd(12)}${m.p50
        .toFixed(5)
        .padEnd(12)}${m.max.toFixed(5).padEnd(12)}${mbs.toFixed(0)}`,
    );
  }
  console.log("");
}

// 平台限定（口径 ⑤）：数字脱离这行就没有意义。
const meta = {
  node: process.version,
  cpu: (await import("node:os")).cpus()[0]?.model ?? "unknown",
  seed: cases.seed,
  rounds,
  warmup,
  note: "同机相对量；wasm-gc/wasm32 双后端；往返口径；不可与 ISSUE #3 混比",
};
console.log("平台：", JSON.stringify(meta));

if (jsonPath) {
  writeFileSync(jsonPath, JSON.stringify({ meta, results }, null, 2));
  console.log(`\n已写出：${jsonPath}`);
}
