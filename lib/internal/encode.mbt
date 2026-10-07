///|
/// 编码内核（**零分配**：`BytesView` 进 / `FixedArray[Byte]` 出）。
///
/// 为什么是 `BytesView`：对齐 rust-base64 的 `AsRef<[u8]>`，且零拷贝
/// （[S1 §4](docs/01-规格/S1-rust-base64-移植可行性分析.md) 的「输入缓冲」一行）。
/// 为什么不是 `String`：`String` 是 UTF-16，字节与字符之间没有免费的桥（[S1 §5.3]）。

///|
/// 估算编码后的字节数（不含 padding 时也按 4 倍上取整）。
///
/// 对齐 rust-base64 的 `internal_encoded_len_estimate`；**不产生输出**，只算长度。
/// 定长输出 API（`encode_slice`）靠它预先分配，是本层零分配能成立的前提。
///
/// TODO(M1)：`((len + 2) / 3) * 4`；须覆盖 `len = 0` 与 `len % 3 ∈ {1,2}` 的边界用例。
pub fn encoded_len(_input : BytesView) -> Int {
  abort("TODO(M1): encoded_len —— 上取整到 4 的倍数")
}

///|
/// 编码内核：把 `input` 编码写入 `out`，返回**实际写入的字节数**。
///
/// 对齐 rust-base64 的 `encode_slice(input, &mut [u8]) -> usize`。
/// 这是 [S2 §2.4](docs/01-规格/S2-现状基线与迁移缺口.md) 定下的**签名命门**之一：
/// `FixedArray[Byte]` 能对齐 Rust 的 `&mut [u8]`，而 `String` 不能。
///
/// 前置：`out.length() >= encoded_len(input)`；不足时返回 `Err(InvalidLength(...))`。
///
/// TODO(M1)：先按「逐 3 字节 → 4 字符」写对（正确性优先）。
/// TODO(M4)：再加「每次读 6 字节 / 写 8 字符」的 4 块展开——**M4 的收益在解码侧，编码侧顺带**。
pub fn encode_into(
  _engine : Engine,
  _input : BytesView,
  _out : FixedArray[Byte],
) -> Result[Int, DecodeError] {
  abort(
    "TODO(M1): encode_into —— 3 字节组 → 4 符号；按 padding 开关补 `=`",
  )
}
