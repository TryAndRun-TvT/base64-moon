// 体积测量 —— **同一把尺子**量所有实现（bench/README.md「体积口径」）。
//
// 【为什么用「增量」而不是绝对值】wasm 文件的绝对值里绝大部分是**运行时**
// （GC、字符串原语、`_start` 样板）——各实现共有，且随工具链版本变化。
// 「引入这一家实现后，exec 大了多少字节」才是可比的量。
// 故 baseline = 一个什么都不做的 wasm-gc exec。
//
// 【gzip -9 为什么也报】分发时走的是压缩后的传输体积；raw 与 gzip 的排序
// 不一定一致（表 / 重复串的压缩率不同），两个都报才不会被单一口径误导。

import { readFileSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
const BENCH = resolve(HERE, "..");

/** 读一个文件，返回 { raw, gzip } 字节数。 */
export function measureSize(path) {
  const bytes = readFileSync(path);
  return { raw: bytes.length, gzip: gzipSync(bytes, { level: 9 }).length };
}

/**
 * 量一组「本仓可控」的产物，返回带增量列的表。
 *
 * 只看本仓产物（baseline + 本库 + core）；Rust / JS 的体积由 `scripts/bench.sh`
 * 直读其产物文件，不进本函数——它们的构建方式完全不同（cargo / node_modules），
 * 混进来会把「同一把尺子」变成「同一张表里的不同尺子」。
 */
export function sizeTable() {
  const B = resolve(BENCH, "_build/wasm-gc/release/build");
  const rows = [
    {
      label: "空 wasm-gc exec（基线）",
      path: resolve(B, "TryAndRun-TvT/base64-moon-size/cmd/empty/empty.wasm"),
      baseline: true,
    },
    {
      label: "base64-moon（本库，最小使用体）",
      path: resolve(B, "TryAndRun-TvT/base64-moon-size/cmd/uselib/uselib.wasm"),
    },
  ];
  const measured = rows.map((r) => ({ ...r, ...measureSize(r.path) }));
  const base = measured.find((r) => r.baseline);
  return measured.map((r) => ({ ...r, deltaRaw: r.raw - base.raw }));
}
