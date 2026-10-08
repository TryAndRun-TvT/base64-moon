// 白盒（包**内**）：锁 `DecodeError` 的**形态**与**构造边界**。
//
// 【为什么这两条必须在这里测】
// 变体的构造点在**定义包**里唯一——本包。外壳 `lib/` 虽是 `pub type` 别名的
// 持有者，却是「其它包」，构造不出变体（`Cannot create values of the read-only type`）。
// 于是「变体没被悄悄改掉」「构造点没被误扩成公共面」这两条，
// 只有在定义包内才测得到。
//
// 【判据来源】rust-base64 0.23.1 的 `DecodeError`（对照见 S1 §3.2）。
// 本文件锁**变体形态**；「反查表 `-1` 约定 + 定义包内可裸写」在 `error_contract_wbtest.mbt`。

///|
/// 白盒：锁 `DecodeError` 的**形态**（回归护栏）——四个变体各自携带**可编程**字段
/// （`offset` / `byte` / `length`），不是展示用字符串。
///
/// 为什么值得单列：`suberror` 的变体若被悄悄改动（如把 `InvalidByte(Int, Byte)`
/// 退化成只带 `String`），差异会被实现细节淹没——而**字段是可编程契约**，
/// 不能靠「有 Err 就行」的断言兜住。这里用最小构造 + 模式匹配把它钉死。
///
/// 判据来源：rust-base64 的 `DecodeError`（对照表见 S1 §3.2）。
test "decode_error_shape_is_structured" {
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

///|
/// 白盒：`Eq` / `Debug` 两个 impl 是**显式登记**的（见 `error.mbt` 末尾的 `extend`），
/// 不是隐式提升的。故内核包外的 `assert_eq` 才拿得到它们。
///
/// 变异点：删掉任一条 `extend`，本用例与全部黑盒断言一起变红。
test "error_impls_are_registered" {
  assert_eq(InvalidByte(0, b'='), InvalidByte(0, b'='))
  assert_eq(InvalidByte(0, b'=') == InvalidByte(1, b'='), false)
  assert_eq(InvalidPadding, InvalidPadding)
  assert_eq(InvalidLength(1) == InvalidLength(2), false)
  assert_eq(DecodeFailed(InvalidPadding), DecodeFailed(InvalidPadding))
  assert_eq(
    DecodeFailed(InvalidPadding) == DecodeFailed(InvalidLength(1)),
    false,
  )
  // 两个 `OutputSliceTooSmall` 是**不同类型**的同名变体，故须写限定名——
  // 这条顺带证明「外壳的两个错误类型没有在包边界上被合并」。
  assert_eq(
    (DecodeSliceError::OutputSliceTooSmall : DecodeSliceError),
    DecodeSliceError::OutputSliceTooSmall,
  )
  assert_eq(
    (EncodeSliceError::OutputSliceTooSmall : EncodeSliceError),
    EncodeSliceError::output_slice_too_small(),
  )
}

///|
/// 白盒：`describe_decode_error` 的展示口径（**人能读**，但不是契约）。
///
/// 这条同时是「`to_hex` 没写错」的护栏：`0x21` 是两位小写十六进制。
/// 公开面那一侧的口径另锁在 `lib/base64_test.mbt` 的 `decode_errors_are_showable`。
test "describe_renders_all_variants" {
  assert_eq(
    describe_decode_error(InvalidByte(4, b'!')),
    "InvalidByte(offset=4, byte=0x21)",
  )
  // 高位字节：`0xfb` 而不是 `0xFB`、也不是只取低 4 位。
  assert_eq(
    describe_decode_error(InvalidByte(0, b'\xfb')),
    "InvalidByte(offset=0, byte=0xfb)",
  )
  assert_eq(
    describe_decode_error(InvalidByte(0, b'\x0f')),
    "InvalidByte(offset=0, byte=0x0f)",
  )
  assert_eq(describe_decode_error(InvalidLength(5)), "InvalidLength(5)")
  assert_eq(
    describe_decode_error(InvalidLastSymbol(1, b'h')),
    "InvalidLastSymbol(offset=1, symbol=0x68)",
  )
  assert_eq(describe_decode_error(InvalidPadding), "InvalidPadding")
}
