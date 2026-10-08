// 白盒（包**内**）：**错误构造边界**的护栏。
//
// 【为什么这条必须在定义包内测】`pub type X = @internal.X` 只搬得动**类型名**，
// 枚举对其它包是**只读**的。于是在外壳 `lib/`（别名持有者，但仍是「其它包」）里
// `Err(InvalidByte(..))` 编译不过（`Cannot create values of the read-only type`）。
// 能构造的地方只有两处：定义包的内部，和**第三方包**（用户代码——
// 它们靠类型推导把变体名带进来）。
//
// 于是「包边界恰好卡在哪儿」这件事**只有在本包测得准**：
//   · 本包能构造   → 官方语义兼容（用户代码写得出 `Err(InvalidByte(4, b'!'))`）；
//   · 外壳构造不出 → 外壳内的错误断言必须按形状判断，不能拼期望值。
// 实测与三格表见 [S5 §3](docs/01-规格/S5-实施裁决与M1落地.md)。

///|
/// 白盒：反查表对非法字节返回 `-1`（解码判定 `InvalidByte` 的唯一依据）。
///
/// `padding` 也必须是 `-1`：它由「位置判据」单独处理
/// （`decode_suffix` 里判 `idx - start < 2`），若与合法符号混同，
/// `"=Zm9v"` 会变成合法输入——判据 4 直接失效。
test "decode_table_marks_invalid_bytes" {
  let table = build_decode_table(Alphabet::standard())
  assert_eq(table['A'.to_int()], 0)
  assert_eq(table['/'.to_int()], 63)
  assert_eq(table['-'.to_int()], -1)
  assert_eq(table['='.to_int()], -1)
  let url = build_decode_table(Alphabet::url_safe())
  assert_eq(url['-'.to_int()], 62)
  assert_eq(url['_'.to_int()], 63)
}

///|
/// 白盒：**定义包内变体可裸写**——这是「官方语义兼容」的那一侧。
///
/// 用户代码（第三方包）与这里的处境相同，故本用例其实是
/// 「`docs` 里承诺的 `Err(InvalidByte(offset, byte))` 写法成立吗」的实证。
test "variants_are_constructible_in_defining_package" {
  let e : DecodeError = InvalidByte(4, b'!')
  match e {
    InvalidByte(offset, byte) => {
      assert_eq(offset, 4)
      assert_eq(byte, b'!')
    }
    _ => abort("InvalidByte 的形态被改动")
  }
  assert_eq(DecodeError::invalid_length(5), InvalidLength(5))
  let e2 : DecodeSliceError = DecodeFailed(InvalidPadding)
  match e2 {
    DecodeFailed(_) => ()
    OutputSliceTooSmall => abort("DecodeFailed 被改动")
  }
}
