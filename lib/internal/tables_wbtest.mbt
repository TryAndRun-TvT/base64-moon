// 白盒（包**内**）：锁**表的内容与不变量**。
//
// 【为什么单列这个文件】表在 M1 就随 `Engine` 落地了，但直到 M3 都没有测试
// （`grep Engine lib/*_wbtest.mbt` → 空）：验收里写着「表只建一次」，
// 却没人验过「表建出来是对的」。
//
// 为什么必须白盒：`decode_table` / `encode_table` 是 `Engine` 的私有字段，
// 黑盒只能验「编解码结果对不对」，验不到「表本身对不对」——
// 而表错了**未必立刻**表现成结果错（见下面 URL-safe 那条：错位 43 格时，
// 标准字母表用例全绿，只有 URL-safe 的少数输入才现形）。
//
// 台账：`docs/01-规格/S6-性能实测与M3裁决.md` §5.1。
// 反查表的「-1 填充约定」另在 `error_contract_wbtest.mbt`（它属解码判据的前提）。

///|
/// 判据 1：反查表的**内容与全覆盖**——合法符号恰好映射到 0..=63，无缺、**无重**。
///
/// 「无重」是真正的不变量：两个符号映射到同一个 6 位值时，解码结果取决于
/// 表里谁后写，是**静默错**。
test "decode_table_covers_symbols_bijectively" {
  let t = build_decode_table(Alphabet::standard())
  assert_eq(t.length(), 256)
  let seen = FixedArray::make(64, false)
  let symbols = Alphabet::standard().symbols
  for i = 0; i < 64; i = i + 1 {
    let v = t[symbols[i].to_int()]
    assert_eq(v, i)
    assert_eq(seen[v], false)
    seen[v] = true
  }
}

///|
/// 判据 2：`encode_table` 的 62 / 63 位——**标准**表是 `+` / `/`。
///
/// 为什么单列这两格而不是整表比对：它们的**下标是 6 位值，不是字符码点**。
/// 写成 `symbols[b'+'.to_int()]` 就会把下标 43（`r` 的槽）改掉，
/// 而 62 / 63 仍是 `+` / `/`——这条错曾真的发生过（[S5 §6.1](docs/01-规格/S5-实施裁决与M1落地.md)）。
test "encode_table_standard_tail" {
  let symbols = Alphabet::standard().symbols
  assert_eq(symbols.length(), 64)
  assert_eq(symbols[62], b'+')
  assert_eq(symbols[63], b'/')
  // `build_encode_table` 直接返回符号表本身（不拷贝），故内容必须一致。
  let et = build_encode_table(Alphabet::standard())
  assert_eq(et[62], b'+')
  assert_eq(et[63], b'/')
}

///|
/// 判据 3（**本文件最重要的一条**）：URL-safe 表是标准表的**独立副本**。
///
/// 两条不变量，缺一不可：
///   ① 62 / 63 换成 `-` / `_`；② **标准表不受影响**——
///   `FixedArray` 是引用语义，少一次 `copy()` 就会让
///   「带不带 `alphabet=` 参数」输出完全相同。
///
/// 这条**能红**：把 `symbols[62] = b'-'` 退回 `symbols[b'+'.to_int()] = b'-'`，
/// 则 62/63 断言红、`symbols[43]` 断言红——复现 S5 §6.1 抓到过的原始 bug。
test "url_safe_is_an_independent_copy" {
  let std = Alphabet::standard()
  let url = Alphabet::url_safe()
  // ① URL-safe 的两个差异位
  assert_eq(url.symbols[62], b'-')
  assert_eq(url.symbols[63], b'_')
  // 其余 62 位必须与标准表**逐位相同**（差且只差 62/63）
  for i = 0; i < 64; i = i + 1 {
    if i != 62 && i != 63 {
      assert_eq(url.symbols[i], std.symbols[i])
    }
  }
  // ② 反向污染检查：读 URL-safe 表不得动到标准表。
  //    这条拦的是「忘了 copy()」——共享引用时两边都会红。
  assert_eq(std.symbols[62], b'+')
  assert_eq(std.symbols[63], b'/')
  // ③ 顺带锁住「下标是 6 位值」这个前提：43 号槽两边都是 `r`，
  //    它是 `b'+'.to_int() = 43` 那个经典错误的落点（42 号槽才是 `q`）。
  assert_eq(std.symbols[43], b'r')
  assert_eq(url.symbols[43], b'r')
  assert_eq(std.symbols[42], b'q')
}

///|
/// 判据 4：`Engine::new` 是**纯构造**——两次建出的表内容逐项相同。
///
/// 这是「建表结果可依赖」的前提，也反过来说明：外壳每调用建一次引擎
/// **没有正确性代价**（只付时间），故 [S6 §2](docs/01-规格/S6-性能实测与M3裁决.md)
/// 裁决「不做复用」是安全的。
test "engine_new_is_pure" {
  let e1 = Engine::new(Alphabet::standard(), Config::default())
  let e2 = Engine::new(Alphabet::standard(), Config::default())
  for i = 0; i < 256; i = i + 1 {
    assert_eq(e1.decode_table[i], e2.decode_table[i])
  }
  for i = 0; i < 64; i = i + 1 {
    assert_eq(e1.encode_table[i], e2.encode_table[i])
  }
  // 配置不进表：表只由字母表决定——这条防止「以后把配置也编进表」。
  let e3 = Engine::new(
    Alphabet::standard(),
    Config::new(false, true, DecodePaddingMode::require_none()),
  )
  for i = 0; i < 256; i = i + 1 {
    assert_eq(e1.decode_table[i], e3.decode_table[i])
  }
  // 不同**字母表**必须给出不同的表（否则 `alphabet=` 形同虚设）。
  let e4 = Engine::new(Alphabet::url_safe(), Config::default())
  assert_eq(e1.decode_table[b'+'.to_int()], 62)
  assert_eq(e4.decode_table[b'+'.to_int()], -1)
  assert_eq(e4.decode_table[b'-'.to_int()], 62)
}
