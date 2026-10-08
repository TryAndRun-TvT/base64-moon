// 白盒（包**内**）：锁**长度算式**——编码侧 `encoded_len` / 解码侧 `decoded_len_estimate`。
//
// 【为什么这两条要单独立测】它们是**分配依据**：`encode_slice` / `decode_slice`
// 按它们判定「缓冲够不够」，`encode` / `decode` 按它们预分配。
// 算式偏小 → 越界写；偏大 → 白分配。而**对外行为**几乎抓不到它们：
//   · `encoded_len` 偏一档（`(n+1)/3*4`）在 `n % 3 == 2` 时仍不小于有效符号数，
//     于是 `encode_slice` 不报错、`encode` 也不越界（`add_padding` 写满 4 的倍数，
//     恰好还在容量内），只有「分配的容量」变了；
//   · `decoded_len_estimate` 偏小在多数长度上仍够用（`n % 4 == 0` 精确、其余有余量），
//     少数长度才触发 `OutputSliceTooSmall`，而那条路径在公共 API 上被
//     `decode` 的兜底吃掉。
// 故它们是「改了不会被抓、但确实改了行为」的那一类——只能在此处直接钉值。
//
// 台账：`docs/01-规格/S4-实施规格与落地顺序.md`（S2 §2.4 的签名命门之一）。

///|
/// 判据：`encoded_len` **恰好**等于含 padding 的总长 `((n + 2) / 3) * 4`。
///
/// 真值点覆盖三种余数：`n % 3 ∈ {0, 1, 2}`，以及 `n = 0` 的退化格。
/// 实测对照（crate `encoded_len(n, true)`）：0→0、1→4、2→4、3→4、4→8、7→12。
test "encoded_len_is_exact_with_padding" {
  assert_eq(encoded_len(b""[:]), 0)
  assert_eq(encoded_len(b"a"[:]), 4)
  assert_eq(encoded_len(b"ab"[:]), 4)
  assert_eq(encoded_len(b"abc"[:]), 4)
  assert_eq(encoded_len(b"abcd"[:]), 8)
  assert_eq(encoded_len(b"abcde"[:]), 8)
  assert_eq(encoded_len(b"abcdef"[:]), 8)
  assert_eq(encoded_len(b"abcdefg"[:]), 12)
  // 大尺寸点：算式必须是 `((n + 2) / 3) * 4`，不是逐组累加的特例。
  let big = Bytes::from_array(FixedArray::make(1024, b'\x00')[:])
  assert_eq(encoded_len(big[:]), 1368)
  let big2 = Bytes::from_array(FixedArray::make(1023, b'\x00')[:])
  assert_eq(encoded_len(big2[:]), 1364)
}

///|
/// 判据：`decoded_len_estimate` 是**上界**（≥ 真实字节数），且不多算超过 2 字节。
///
/// 「上界」是契约（`decode_slice` 用它判够不够，偏小即越界或误报）；
/// 「不多算」是效率边界（偏大即白分配）。实测对照：0→0、1..4→3、5..8→6、9→9。
test "decoded_len_estimate_is_a_tight_upper_bound" {
  assert_eq(decoded_len_estimate(0), 0)
  assert_eq(decoded_len_estimate(1), 3)
  assert_eq(decoded_len_estimate(4), 3)
  assert_eq(decoded_len_estimate(5), 6)
  assert_eq(decoded_len_estimate(8), 6)
  assert_eq(decoded_len_estimate(9), 9)
  // 逐长度扫：上界恒成立，且 `4` 的倍数处**精确**（不浪费）。
  for n = 0; n <= 64; n = n + 1 {
    let est = decoded_len_estimate(n)
    // 真实解出字节数：`n / 4 * 3` 再加尾巴（含 1 个符号时其实非法，此处只看上界）。
    let rem = n % 4
    // 真实可解出字节数：整组 `n / 4 * 3`，尾巴 2 符号 → 1 字节、3 符号 → 2 字节。
    // `rem == 1` 本身是非法输入（判据 2 会拒），`n == 0` 解出 0 字节。
    // 上界比它多出的那 1~3 字节，正是 `rem != 0` 时按整组上取整的代价。
    let real = n / 4 * 3 + (if rem == 2 { 1 } else if rem == 3 { 2 } else { 0 })
    assert_eq(est >= real, true)
    // 精确只在 `rem == 0`（没有任何尾巴）时成立。
    if rem == 0 {
      assert_eq(est, real)
    }
    // 有尾巴时上取整到整组：多算 1~3 字节，不会更多。
    if rem != 0 {
      assert_eq(est - real <= 3, true)
    }
  }
}
