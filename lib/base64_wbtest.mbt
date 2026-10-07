///|
test "decode_table_marks_invalid_bytes" {
  // 白盒：反查表对非法字节返回 -1（`decode` 依赖该约定判定 Err）
  let table = decode_table(Standard)
  assert_eq(table['A'.to_int()], 0)
  assert_eq(table['/'.to_int()], 63)
  assert_eq(table['-'.to_int()], -1)
  let url = decode_table(UrlSafe)
  assert_eq(url['-'.to_int()], 62)
  assert_eq(url['_'.to_int()], 63)
}
