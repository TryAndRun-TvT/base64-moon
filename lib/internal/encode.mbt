///|
/// 编码内核（**零分配**：`BytesView` 进 / `FixedArray[Byte]` 出）。
///
/// 为什么是 `BytesView`：对齐 crate 的 `AsRef<[u8]>`，且零拷贝
/// （[S1 §4](docs/01-规格/S1-rust-base64-移植可行性分析.md) 的「输入缓冲」一行）。
/// 为什么不是 `String`：`String` 是 UTF-16，字节与字符之间没有免费的桥（[S1 §5.3]）。

///|
/// 估算编码后的字节数（**含 padding**，即对齐 crate 的 `encoded_len(n, true)`）。
///
/// 对齐 crate 的 `internal_encoded_len_estimate`；**不产生输出**，只算长度。
/// 定长输出 API（`encode_slice`）靠它预先分配，是本层零分配能成立的前提。
///
/// 口径：`((len + 2) / 3) * 4`。`len = 0` 时为 0；`len % 3 ∈ {1,2}` 时按整组上取整。
/// 实测对照（crate `encoded_len(n, true)`）：0→0、1→4、2→4、3→4、4→8、7→12。
pub fn encoded_len(input : BytesView) -> Int {
  (input.length() + 2) / 3 * 4
}

///|
/// 编码内核：把 `input` 编码写入 `out`，返回**实际写入的有效符号数**（不含 padding）。
///
/// 对齐 crate 的 `internal_encode`。这是 [S2 §2.4](docs/01-规格/S2-现状基线与迁移缺口.md)
/// 定下的**签名命门**之一：`FixedArray[Byte]` 能对齐 Rust 的 `&mut [u8]`，而 `String` 不能。
///
/// **本函数不写 padding**（唯一写点是 `pad.mbt` 的 `add_padding`，见 S4 §2.1）。
///
/// 前置：`out.length() >= encoded_len(input)`。
pub fn encode_into(
  engine : Engine,
  input : BytesView,
  out : FixedArray[Byte],
) -> Int {
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
