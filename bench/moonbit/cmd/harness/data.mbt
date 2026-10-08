///|
/// 数据生成：`det_bytes(n, seed)` 的**唯一实现**，各侧共享同一数据式。
///
/// 【为什么生成式必须钉死并共享】跨语言对比的头号假象是「比的是数据搬运」。
/// `wasm-gc` 的 `Bytes` 是 GC 数组、**没有线性内存指针**，无法从 Node 侧灌入大 buffer；
/// 唯一干净的做法是**让被测侧自己按同一 seed 生成**。各侧（MoonBit / Rust / JS）
/// 都实现同一个式子，「输入相同」于是可验证，而不只是约定（bench/README.md 口径 ①）。
///
/// 式子与主仓差分基线**同源**，便于交叉引用：
/// `b[i] = (i * 37 + 11 + seed) & 0xFF`。
pub fn det_bytes(n : Int, seed : Int) -> FixedArray[Byte] {
  let buf = FixedArray::make(n, b'\x00')
  let mut i = 0
  while i < n {
    buf[i] = ((i * 37 + 11 + seed) & 0xFF).to_byte()
    i = i + 1
  }
  buf
}

///|
/// 字节校验和：把所有字节累加进一个 `Int`。
///
/// 【为什么需要它】`wasm-gc` 的 `Bytes` / `String` 是 GC 对象，Node 取不出内容，
/// 跨界只能用 `Int`。校验和把「两家输出是否逐位相同」压成一个可比对的 `Int`——
/// 它同时是**防 DCE 的锚**（结果必须回传才算数，见 bench/README.md 口径 ④）。
pub fn checksum(b : BytesView) -> Int {
  let mut acc = 0
  let mut i = 0
  while i < b.length() {
    acc = acc + b[i].to_int()
    i = i + 1
  }
  acc
}
