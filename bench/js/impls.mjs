// JS 侧各实现 —— 与 MoonBit / Rust harness **同数据式、同校验和式**。
//
// 【口径要素 ①：数据在被测侧生成】`detBytes` 是 `b[i] = (i*37+11+seed)&0xFF`
// 的 JS 复刻；输入不进任何跨界通道，「比的是算法不是搬运」。
//
// 【node Buffer 的定位】它是 **C++ + SIMD 的参照系，不是可比对象**：
// 它既不是 JS 实现，也不受 JS 引擎优化策略影响。引用其数字必须带这个限定
// （bench/README.md 口径 ⑤；S2 §5 的「不可混比」纪律）。

import * as base64js from "base64-js";
import { fromUint8Array, toUint8Array } from "js-base64";

/** 数据生成：与 MoonBit `det_bytes` / Rust `det` 同式。 */
export function detBytes(n, seed) {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 37 + 11 + seed) & 0xff;
  return b;
}

/** 字节校验和：与 MoonBit `checksum` / Rust `checksum` 同式（Int 累加）。 */
export function checksum(b) {
  let acc = 0;
  for (let i = 0; i < b.length; i++) acc = (acc + b[i]) | 0;
  return acc;
}

/** 把 base64 文本按 ASCII 读成字节 —— 对齐 MoonBit 的 `@utf8.encode`。 */
export function asciiBytes(s) {
  const b = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) b[i] = s.charCodeAt(i) & 0xff;
  return b;
}

/**
 * JS 侧实现注册表。
 *
 * `kind` 标注**可比性等级**（bench.sh 的表格据此分组，不靠人记）：
 *   · `"js"`     —— 纯 JS，与本库同属「语言运行时之上的实现」，**直接可比**；
 *   · `"native"` —— C++/SIMD 参照系，**不可直接比**，只作上界参照。
 */
export const IMPLS = [
  {
    name: "base64-js",
    kind: "js",
    roundtrip: (src) => base64js.toByteArray(base64js.fromByteArray(src)),
    encodeE2E: (src) => base64js.fromByteArray(src),
    encodeChecksum: (src) => checksum(asciiBytes(base64js.fromByteArray(src))),
  },
  {
    name: "js-base64",
    kind: "js",
    roundtrip: (src) => toUint8Array(fromUint8Array(src)),
    encodeE2E: (src) => fromUint8Array(src),
    encodeChecksum: (src) => checksum(asciiBytes(fromUint8Array(src))),
  },
  {
    name: "node Buffer",
    kind: "native",
    // 注意：`new Uint8Array(str, "base64")` 会把 "base64" 当**长度**（第二个形参是
    // lengthOrArrayLike），故必须走 `Buffer.from(str, "base64")` 再转。这个坑
    // 在 [S10 §2] 那类「错得一致」的检查里是抓不到的——只有跨实现校验和能抓。
    roundtrip: (src) =>
      new Uint8Array(Buffer.from(Buffer.from(src).toString("base64"), "base64")),
    encodeE2E: (src) => Buffer.from(src).toString("base64"),
    encodeChecksum: (src) =>
      checksum(asciiBytes(Buffer.from(src).toString("base64"))),
  },
];
