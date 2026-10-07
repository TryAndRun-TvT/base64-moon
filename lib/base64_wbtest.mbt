// 白盒（包**内**）：可以直连私有实现，也能看见内核的错误变体。
//
// 为什么要单独有这个文件而不是把断言塞进 `base64_test.mbt`：
// `pub type DecodeError = @internal.DecodeError` 这条别名**只搬得动类型名**，
// 变体在别名所属的包里是**只读**的——本包（`lib/`）里 `Err(InvalidByte(...))`
// 编译不过（`Cannot create values of the read-only type`）。
// 可构造的两处只有：定义它们的 `lib/internal`，以及**第三方包**（用户代码 /
// 包外黑盒测试，靠类型推导带进来）。实录见
// [S5 §4](docs/01-规格/S5-实施裁决与M1落地.md)。

///|
/// 白盒：反查表对非法字节返回 `-1`（解码判定 `InvalidByte` 的唯一依据）。
test "decode_table_marks_invalid_bytes" {
  let table = @internal.build_decode_table(@internal.Alphabet::standard())
  assert_eq(table['A'.to_int()], 0)
  assert_eq(table['/'.to_int()], 63)
  assert_eq(table['-'.to_int()], -1)
  // padding 也必须是 -1：它由位置判据单独处理，混同即让 `=Zm9v` 变成合法输入。
  assert_eq(table['='.to_int()], -1)
  let url = @internal.build_decode_table(@internal.Alphabet::url_safe())
  assert_eq(url['-'.to_int()], 62)
  assert_eq(url['_'.to_int()], 63)
}
