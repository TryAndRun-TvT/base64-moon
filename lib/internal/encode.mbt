///|
/// 编码内核（**零分配**：`BytesView` 进 / `FixedArray[Byte]` 出）。
///
/// 为什么是 `BytesView`：对齐 crate 的 `AsRef<[u8]>`，且零拷贝。
/// 为什么不是 `String`：`String` 是 UTF-16，字节与字符之间没有免费的桥
/// （[S1 §5.3](docs/01-规格/S1-rust-base64-移植可行性分析.md)）。

///|
/// 估算编码后的字节数（**含 padding**，对齐 crate 的 `encoded_len(n, true)`）。
///
/// 口径 `((len + 2) / 3) * 4`：`len = 0` 时为 0；`len % 3 ∈ {1,2}` 时按整组上取整。
/// 实测对照（crate `encoded_len(n, true)`）：0→0、1→4、2→4、3→4、4→8、7→12。
///
/// 定长输出 API（`encode_slice`）靠它预先分配——这是零分配能成立的前提。
pub fn encoded_len(input : BytesView) -> Int32 {
  (input.length() + 2) / 3 * 4
}

///|
/// 编码内核：把 `input` 编码写入 `out`，返回**实际写入的有效符号数**（不含 padding）。
///
/// 对齐 crate 的 `internal_encode`。签名里的 `FixedArray[Byte]` 对齐 Rust 的
/// `&mut [u8]`——`String` 做不到这一点，这是定长输出 API 的前提。
///
/// **本函数不写 padding**（唯一写点是 `pad.mbt` 的 `add_padding`）：
/// 分块编码器要逐块输出，内核一旦自己补 `=` 就没法复用了。
///
/// 前置：`out.length() >= encoded_len(input)`。
pub fn encode_into(
  engine : Engine,
  input : BytesView,
  out : FixedArray[Byte],
) -> Int32 {
  let table = engine.encode_table
  let n = input.length()
  let mut i = 0
  let mut o = 0
  while i + 2 < n {
    let (b0, b1, b2) = (
      input[i].to_int(),
      input[i + 1].to_int(),
      input[i + 2].to_int(),
    )
    out[o] = table[b0 >> 2]
    out[o + 1] = table[((b0 & 0x03) << 4) | (b1 >> 4)]
    out[o + 2] = table[((b1 & 0x0F) << 2) | (b2 >> 6)]
    out[o + 3] = table[b2 & 0x3F]
    i += 3
    o += 4
  }
  // 尾巴：`n - i` ∈ {0, 1, 2}，只写有效符号，不补 `=`。
  match n - i {
    1 => {
      let b0 = input[i].to_int()
      out[o] = table[b0 >> 2]
      out[o + 1] = table[(b0 & 0x03) << 4]
      o += 2
    }
    2 => {
      let (b0, b1) = (input[i].to_int(), input[i + 1].to_int())
      out[o] = table[b0 >> 2]
      out[o + 1] = table[((b0 & 0x03) << 4) | (b1 >> 4)]
      out[o + 2] = table[(b1 & 0x0F) << 2]
      o += 3
    }
    _ => ()
  }
  o
}
