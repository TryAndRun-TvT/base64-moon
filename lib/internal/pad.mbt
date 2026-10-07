///|
/// 补 padding：**本库唯一写 padding 字节的地方**。
///
/// 为什么必须单点（[S4 §2.1](docs/01-规格/S4-实施规格与落地顺序.md)）：
/// crate 的 `encode_with_padding` 在独立函数里补 `=`，而内核 `internal_encode`
/// **自身不写 padding**（否则分块编码器无法逐块输出）。
/// 照抄这条纪律后，`encode_into` 只写有效符号——于是 `encode_slice` 的
/// 「缓冲够不够」判定只看有效符号数，不会被 padding 搅乱。

///|
/// 在 `out[written..]` 写入 `(4 - written % 4) % 4` 个 padding 字节，返回写入个数。
///
/// 前置：`out` 的剩余空间足以容纳 padding（调用方按 `encoded_len` 算过）。
pub fn add_padding(
  written : Int,
  padding : Byte,
  out : FixedArray[Byte],
) -> Int {
  let pad_bytes = (4 - written % 4) % 4
  for i = 0; i < pad_bytes; i = i + 1 {
    out[written + i] = padding
  }
  pad_bytes
}
