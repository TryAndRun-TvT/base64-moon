// 白盒（包**内**）：锁 `add_padding` 的**个数**与**写回位置**。
//
// 【为什么这个函数值一个白盒文件】它是全库**唯一**写 padding 字节的地方
// （见 `pad.mbt` 的纪律说明），而它的输出在「结果对了」这件事上**几乎不可见**：
//   · `written % 4 == 0` 时补 0 个——报文里根本没有 padding，改错也不显形；
//   · 而 `(4 - written % 4) % 4` 的**外层 `% 4`** 是那个易漏的括号：
//     去掉它，`written % 4 == 0` 时会补 4 个 `=`，`"Zm9v"` 变成 `"Zm9v===="`。
// 公共 API 那一层只覆盖了「非零 padding 个数」的少数长度，
// 故「个数表」与「写回位置」在本文件直接钉死。

///|
/// 判据：`(written % 4, padding 个数)` 的四格真值表全对。
///
/// 四格不是「更多用例」，是四个**语义不同的分支**：
///   0 → 0（整组，不要 padding）；1 → 3；2 → 2；3 → 1。
/// 边界（`written % 4 == 0`）正是外层 `% 4` 的落点，也是唯一会被
/// 「顺手化简」掉的格。
test "add_padding_count_table" {
  let out = FixedArray::make(8, b'\x00')
  assert_eq(add_padding(0, b'=', out), 0)
  assert_eq(add_padding(1, b'=', out), 3)
  assert_eq(add_padding(2, b'=', out), 2)
  assert_eq(add_padding(3, b'=', out), 1)
  assert_eq(add_padding(4, b'=', out), 0)
  assert_eq(add_padding(5, b'=', out), 3)
  assert_eq(add_padding(8, b'=', out), 0)
}

///|
/// 判据：字节写在 `out[written..]`，**不动** `written` 之前的内容。
///
/// 这条锁的是「单点写 padding」的前提——若它反向写、或从 0 开始写，
/// 内核刚写进去的有效符号就被覆盖了，而这类错在短输入上可能表现为
/// 「输出少了几个字符」而不是崩溃。
test "add_padding_writes_after_written" {
  let out = FixedArray::make(6, b'.')
  let n = add_padding(2, b'=', out)
  assert_eq(n, 2)
  assert_eq(out[0], b'.')
  assert_eq(out[1], b'.')
  assert_eq(out[2], b'=')
  assert_eq(out[3], b'=')
  assert_eq(out[4], b'.')
  assert_eq(out[5], b'.')
  // padding 字符是可配的（Crypt 用 `.`）：换成别的字符必须原样落盘。
  let out2 = FixedArray::make(4, b'\x00')
  assert_eq(add_padding(3, b'.', out2), 1)
  assert_eq(out2[3], b'.')
}
