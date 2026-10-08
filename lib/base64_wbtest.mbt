// 白盒（包**内**）：直连 `lib/internal/` 的私有实现。
//
// 与 `base64_test.mbt`（黑盒，只碰 `pub` API）的分工：这里锁的是**内核数据结构本身**
// （表的内容与不变量），黑盒验不到——且表错了**未必立刻**表现成结果错。
// 内核**类型形态**的护栏另在 `lib/internal/error_wbtest.mbt`；
// 别名只读那条包边界约束见 [S5 §4](docs/01-规格/S5-实施裁决与M1落地.md)。

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
