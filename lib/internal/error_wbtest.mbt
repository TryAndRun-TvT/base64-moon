///|
/// 白盒：锁 `DecodeError` 的**形态**（M1 实现落地前的护栏）。
///
/// 为什么骨架期就要有这条：`suberror` 的变体一旦定下，M1 就得按此实现；
/// 若变体被悄悄改动（如把 `InvalidByte(Int, Byte)` 退化成只带 `String`），
/// 差异会被 M1 的几百行实现淹没。这里用最小构造 + 模式匹配把它钉死。
///
/// 判据来源：rust-base64 的 `DecodeError`（对照表见 S1 §3.2）。
test "decode_error_shape_is_structured" {
  // 四个变体都携带**可编程**字段（offset / byte / length），不是展示用字符串。
  let e : DecodeError = InvalidByte(3, b'!')
  match e {
    InvalidByte(offset, byte) => {
      assert_eq(offset, 3)
      assert_eq(byte, b'!')
    }
    _ => abort("InvalidByte 的形态被改动")
  }
  let e2 : DecodeError = InvalidLength(5)
  match e2 {
    InvalidLength(n) => assert_eq(n, 5)
    _ => abort("InvalidLength 的形态被改动")
  }
  let e3 : DecodeError = InvalidLastSymbol(3, b'h')
  match e3 {
    InvalidLastSymbol(offset, symbol) => {
      assert_eq(offset, 3)
      assert_eq(symbol, b'h')
    }
    _ => abort("InvalidLastSymbol 的形态被改动")
  }
  let e4 : DecodeError = InvalidPadding
  match e4 {
    InvalidPadding => ()
    _ => abort("InvalidPadding 的形态被改动")
  }
}

///|
/// 白盒：锁 `DecodePaddingMode` 三态齐全（对齐 rust-base64，见 S1 §3.2）。
test "decode_padding_mode_has_three_states" {
  let modes : Array[DecodePaddingMode] = [
    Indifferent,
    RequireCanonical,
    RequireNone,
  ]
  assert_eq(modes.length(), 3)
}
