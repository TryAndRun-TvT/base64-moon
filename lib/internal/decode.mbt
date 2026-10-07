///|
/// 解码内核（**零分配**：`BytesView` 进 / `FixedArray[Byte]` 出）。
///
/// 与编码侧的关键差别：解码入参**绝不能**是 `String`。
/// 理由（[S1 §5.3](docs/01-规格/S1-rust-base64-移植可行性分析.md)）：
/// `String` 是 UTF-16，按 code unit 取字节等于先把字节塞进 UTF-16 再取出——语义与性能双输。
/// 这也是 [S2 §2.4](docs/01-规格/S2-现状基线与迁移缺口.md) 把「`decode` 收 `String`」
/// 判为**签名错误**（而非优化空间）的原因。

///|
/// 估算解码后的字节数上界（用于预分配输出缓冲）。
///
/// 对齐 rust-base64 的 `internal_decoded_len_estimate`。
/// 上界而非精确值：非法输入会被拒绝，故不必为错误输入算准。
///
/// TODO(M1)：`(len / 4) * 3` 再按余数补；须处理含 / 不含 padding 两种输入。
pub fn decoded_len_estimate(_input : BytesView) -> Int {
  abort(
    "TODO(M1): decoded_len_estimate —— 4 符号组 → 3 字节的上界",
  )
}

///|
/// 解码内核：把 `input` 解到 `out`，返回**实际写入的字节数**。
///
/// 对齐 rust-base64 的 `decode_slice(input, &mut [u8]) -> Result<usize, _>`。
///
/// 本函数是 [S2 §2.1](docs/01-规格/S2-现状基线与迁移缺口.md) 四条判据的**唯一落点**：
///   1. 混入非字母表字节 → `InvalidByte(offset, byte)`（**须带 offset**，现状缺）；
///   2. 末尾有效符号数 `% 4 == 1` → `InvalidLength(len)`（**现状缺**：`decode("Z")` 得 `Ok(b"")`）；
///   3. 末符号低位冗余位非零 → `InvalidLastSymbol(offset, byte)`（**现状缺**：`decode("Zh==")` 得 `Ok(b"f")`）；
///   4. padding 数量 / 位置不合 `padding_mode` → `InvalidPadding`（**现状缺**：多余 `=` 被静默吞掉）。
///
/// TODO(M1)：先按「逐字符累积」写对四条判据，再谈速度（正确性优先）。
/// TODO(M4)：改为「4 字符 → 3 字节」展开——实测 1.6–2.0×（[S1 §6.1]），
///   且**不依赖** SIMD、**不依赖**物化改动，是当前唯一证据充分的性能项。
pub fn decode_into(
  _engine : Engine,
  _input : BytesView,
  _out : FixedArray[Byte],
) -> Result[Int, DecodeError] {
  abort("TODO(M1): decode_into —— 四条判据；M4 换 4 字符展开")
}

///|
/// 后缀校验：一次回答「末尾 2~4 个符号是否合法」。
///
/// 单列的理由（[S1 §3.1](docs/01-规格/S1-rust-base64-移植可行性分析.md)）：
/// rust-base64 的 `decode_suffix.rs` 有 170 行专写这一段，它是**最容易漏的一块**——
/// 四条判据里有三条（2 / 3 / 4）都落在这里，且组合很多
/// （4 错误 × 3 padding 模式 × 冗余位开关）。
///
/// 建议：原样搬成 `Result` 分支（判据与语言无关），**不要**合并进主循环。
///
/// TODO(M1)：`decode_into` 处理完整 4 符号组，本函数处理剩下的尾巴。
pub fn decode_suffix(
  _engine : Engine,
  _leftover : BytesView,
  _acc : Ref[Int],
  _bits : Ref[Int],
  _out : FixedArray[Byte],
  _written : Ref[Int],
) -> Result[Unit, DecodeError] {
  abort("TODO(M1): decode_suffix —— 判据 2/3/4 的唯一落点")
}
