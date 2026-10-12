// 黑盒（包**外**）：M5 —— 语义矩阵（长度全扫 × 配置叉积）。
//
// 【这一层守什么】
// [S4 §8](docs/01-规格/S4-实施规格与落地顺序.md) 把 M5 定义为**持续护栏**：
// 「把长度全扫 × 配置叉积固化成测试，让后续任何改动都过一遍」。
// 判据不是「跑了多少组合」，而是**覆盖了多少条不变量**（AGENTS.md §三.2 铁律 6）：
//   ① 往返不变量；② 长度上界；③ 冗余位不变量；④ padding 不变量。
//
// 【为什么这些用例能被「真值」约束】
// 矩阵的正确性不靠「跑一遍记下自己的输出」（AGENTS.md §三.2 铁律 3 禁止
// `actual == actual`），而靠**四条结构性不变量**——每条都独立于实现：
// 往返是 encode/decode 互逆；长度上界是 RFC 4648 的编码定义；冗余位与 padding
// 不变量直接来自 §3.5。此外另有与 Python stdlib 的**定值**对拍（见文件末
// `matrix_matches_python_reference`）。
//
// 台账：`docs/01-规格/S9-M5语义矩阵与32位装载裁决.md` §2。

// ── 矩阵数据轴（**黑盒私有**：放在测试文件内，不进公共 API） ─────────────────
//
// 【为什么不放 `lib/` 的导出面】[S5 §3.5](docs/01-规格/S5-实施裁决与M1落地.md)
// 的纪律是「宁可多几个断言器，也不扩公共面」。数据生成器只为测试服务，
// 若导出即成为对外契约（`moon info` 可见），与「公共面最小」相悖。
// `*_test.mbt` 编译在包**外**，故这两个 `fn` 在此文件内是私有实现细节。

///|
/// 确定性数据源：`raw(i) = (i * 37 + 11) & 0xFF`。
/// 不用 `@random` 的理由：它依赖执行顺序（AGENTS.md §三.2 铁律 7），且黄金值会漂移。
fn det_bytes(n : Int32) -> Bytes {
  let a = FixedArray::make(n, b'\x00')
  for i = 0; i < n; i = i + 1 {
    a[i] = ((i * 37 + 11) & 0xFF).to_byte()
  }
  Bytes::from_array(a[:])
}

///|
/// 长度扫描集：`0..=64` 逐长度 + 跨越「整组 / 大尺寸」的边界点。
/// 「3 字节 → 4 符号」与 padding 的周期最小公倍数是 12，故 `0..=64` 已覆盖
/// 全部 12 种余数组合；大尺寸点是为了让「整块 vs 尾块」的分界也进矩阵。
fn det_lengths() -> Array[Int32] {
  let xs : Array[Int32] = []
  for n = 0; n <= 64; n = n + 1 {
    xs.push(n)
  }
  for n in [127, 128, 129, 130, 255, 256, 257, 1023, 1024, 1025, 4095, 4096] {
    xs.push(n)
  }
  xs
}

// ── ① 往返不变量 ───────────────────────────────────────────────────────────
//
// `decode(encode(x, padding=p), mode=m) == x`，在合法组合内。
//
// 合法性边界（来自 crate 实测，见 S5 §2.2）：`RequireNone` 拒绝任何 padding，
// 故 `padding=false` 的输出在 `RequireNone` 下可解、`padding=true` 的在
// 「有 padding」时不可解；`Indifferent` 与 `RequireCanonical` 都接受规范输出。

///|
test "matrix_roundtrip_standard" {
  for n in det_lengths() {
    let raw = det_bytes(n)
    // 默认形态（padding=true / RequireCanonical）必须恒可往返。
    assert_eq(@lib.decode(@utf8.encode(@lib.encode(raw))[:]).unwrap(), raw)
    // 无 padding 形态在 Indifferent 下必须可往返（URL-safe 场景的惯例组合）。
    let np = @utf8.encode(@lib.encode(raw, padding=false))
    assert_eq(
      @lib.decode(np[:], padding_mode=@lib.indifferent_mode).unwrap(),
      raw,
    )
    // 无 padding 形态在 RequireNone 下也必须可往返——它本来就没有 `=`。
    assert_eq(
      @lib.decode(np[:], padding_mode=@lib.require_none_mode).unwrap(),
      raw,
    )
  }
}

///|
test "matrix_roundtrip_urlsafe" {
  let url = @lib.Alphabet::url_safe()
  for n in det_lengths() {
    let raw = det_bytes(n)
    assert_eq(
      @lib.decode(@utf8.encode(@lib.encode(raw, alphabet=url))[:], alphabet=url).unwrap(),
      raw,
    )
    let np = @utf8.encode(@lib.encode(raw, alphabet=url, padding=false))
    assert_eq(
      @lib.decode(np[:], alphabet=url, padding_mode=@lib.indifferent_mode).unwrap(),
      raw,
    )
  }
}

// ── ② 长度上界不变量 ───────────────────────────────────────────────────────
//
// RFC 4648 §4 的编码长度定义：`len(encode(x, padding=true)) == ((n+2)/3)*4`。
// 「上界」的含义是：任何正确实现都不会超过这个值，且恰好取到它（padding=true）。

///|
test "matrix_encoded_length_exact" {
  for n in det_lengths() {
    let raw = det_bytes(n)
    let with_pad = @lib.encode(raw)
    // padding=true 时**恰好**等于 RFC 的 `((n+2)/3)*4`，不是「不超过」。
    assert_eq(with_pad.length(), (n + 2) / 3 * 4)
    // 无 padding 时恰好是有效符号数：`n/3*4 + {0,2,3}[n%3]`。
    let np = @lib.encode(raw, padding=false)
    let expect_np = n / 3 * 4 +
      (if n % 3 == 1 { 2 } else if n % 3 == 2 { 3 } else { 0 })
    assert_eq(np.length(), expect_np)
    // `with_pad.length()` 是含 `=` 的总长，`np.length()` 是有效符号数，差即 `=` 个数：
    //   n%3 == 0 → 0；n%3 == 1 → 2；n%3 == 2 → 1。
    // （注意**不是** `(4 - n%3) % 4`——那是「符号到 4 的补数」，
    //   `n%3 == 1` 时末组只有 2 个符号，补数 2 而非 3。这条算式本身容易写错，
    //   故此处同时钉住三个分支的取值。）
    let pad_count = if n % 3 == 0 { 0 } else if n % 3 == 1 { 2 } else { 1 }
    assert_eq(with_pad.length() - np.length(), pad_count)
    // 且总长恒为 4 的倍数、有效符号数恒 < 4 的倍数（除 n%3==0）。
    assert_eq(with_pad.length() % 4, 0)
    if n % 3 != 0 {
      assert_eq(np.length() % 4 != 0, true)
    }
  }
}

///|
test "matrix_encoded_len_slice_is_tight" {
  // `encode_slice` 的「够不够」判定必须与真实写入长度**恰好吻合**：
  // 少一字节必须 `Err`，正好必须 `Ok` 且长度等于真实符号数。
  // 这条锁的是「长度估算与内核实际写入不脱节」——脱节时缓冲区要么浪费要么越界。
  for n in det_lengths() {
    let raw = det_bytes(n)
    let full = @lib.encode(raw)
    let exact = FixedArray::make(full.length(), b'\x00')
    assert_eq(@lib.encode_slice(raw[:], exact), Ok(full.length()))
    if full.length() > 0 {
      let short = FixedArray::make(full.length() - 1, b'\x00')
      match @lib.encode_slice(raw[:], short) {
        Err(OutputSliceTooSmall) => ()
        Ok(n) => fail("期望 OutputSliceTooSmall，实际 Ok(\{n})")
      }
    }
  }
}

// ── ③ 冗余位不变量 ─────────────────────────────────────────────────────────
//
// RFC 4648 §3.5：末尾符号的**低位冗余位**必须为零（严格模式）。
// 这条不变量在规范上等价于「`Zg==` 与 `Zh==` 可区分」——两者解出同一字节，
// 但后者携带了被丢弃的位。

///|
test "matrix_trailing_bits_invariant" {
  // `"Zg"` 与 `"Zh"` 是 RFC 原文那对「同值不同规范」的样本（S4 §4.2 引用过）。
  // 严格：`Zh` 报 `InvalidLastSymbol`；宽容：两者都解得 `b"f"`。
  match @lib.decode(b"Zh=="[:]) {
    Err(InvalidLastSymbol(offset, symbol)) => {
      assert_eq(offset, 1)
      assert_eq(symbol, b'h')
    }
    _ => fail("期望 InvalidLastSymbol(1, 'h')")
  }
  assert_eq(@lib.decode(b"Zh=="[:], allow_trailing_bits=true).unwrap(), b"f")
  assert_eq(@lib.decode(b"Zg=="[:], allow_trailing_bits=true).unwrap(), b"f")
  // 3 符号形态同理：`"Zm8="` 是 `b"fo"` 的规范形；`"Zm9="` 的末符号 `9` 冗余位非零。
  // 报错 offset 是**末符号自己的下标 2**（不是 `=` 的 3）——`=` 根本不参与符号判定。
  assert_eq(@lib.decode(b"Zm8="[:]).unwrap(), b"fo")
  match @lib.decode(b"Zm9="[:]) {
    Err(InvalidLastSymbol(offset, symbol)) => {
      assert_eq(offset, 2)
      assert_eq(symbol, b'9')
    }
    _ => fail("期望 InvalidLastSymbol(2, '9')")
  }
  assert_eq(@lib.decode(b"Zm9="[:], allow_trailing_bits=true).unwrap(), b"fo")
  // 关键：**改了冗余位不影响解出的字节**——这正是「不可区分」的危害。
  assert_eq(@lib.decode(b"Zg=="[:]).unwrap(), b"f")
  assert_eq(@lib.decode(b"Zh=="[:], allow_trailing_bits=true).unwrap(), b"f")
}

///|
test "matrix_trailing_bits_allow_is_superset" {
  // 不变量：`allow_trailing_bits=true` 的接受集 ⊇ `false` 的接受集。
  // 逐长度扫一遍，确保「放宽」不会在某处反而收紧（放宽实现时容易写反）。
  for n in det_lengths() {
    let raw = det_bytes(n)
    let encoded = @utf8.encode(@lib.encode(raw))
    // 规范编码在两种模式下都必须可解。
    assert_eq(@lib.decode(encoded[:]).unwrap(), raw)
    assert_eq(@lib.decode(encoded[:], allow_trailing_bits=true).unwrap(), raw)
  }
}

// ── ④ padding 不变量 ───────────────────────────────────────────────────────

///|
test "matrix_padding_invariant" {
  for n in det_lengths() {
    let raw = det_bytes(n)
    let np = @utf8.encode(@lib.encode(raw, padding=false))
    // `padding=false` 的输出**恒**不含 `=`。
    for i = 0; i < np.length(); i = i + 1 {
      if np[i] == b'=' {
        abort(
          "padding=false 输出含 `=`：n=" +
          n.to_string() +
          " 位置 " +
          i.to_string(),
        )
      }
    }
    // 且当 `n % 3 != 0` 时长度 `% 4 != 0`；`n % 3 == 0` 时 `% 4 == 0`。
    if n % 3 == 0 {
      assert_eq(np.length() % 4, 0)
    } else {
      assert_eq(np.length() % 4 != 0, true)
    }
    // `RequireNone` 下无 padding 输出必须可解；有 padding 输出必须被拒（当 n%3!=0）。
    assert_eq(
      @lib.decode(np[:], padding_mode=@lib.require_none_mode).unwrap(),
      raw,
    )
    if n % 3 != 0 {
      let with_pad = @utf8.encode(@lib.encode(raw))
      match @lib.decode(with_pad[:], padding_mode=@lib.require_none_mode) {
        Err(InvalidPadding) => ()
        _ => fail("期望 InvalidPadding")
      }
    }
  }
}

// ── ⑤ 与 Python stdlib 的**定值**对拍（黄金值出处：CPython base64） ────────
//
// 前面四条是**结构性**不变量（不依赖任何参照实现）。这一条补上**定值**真值：
// 前 8 个长度的期望串由 CPython `base64.b64encode` 产出，硬编码于此。
// 生成命令（复跑见 S9 §5）：
//   python3 -c "import base64;[print(n, base64.b64encode(bytes((i*37+11)&0xFF for i in range(n))).decode()) for n in range(8)]"

///|
test "matrix_matches_python_reference" {
  // 黄金值来源：CPython 3 `base64.b64encode`，数据式子与
  // `deterministic_bytes` 相同（`(i*37+11)&0xFF`）。
  assert_eq(@lib.encode(det_bytes(0)), "")
  assert_eq(@lib.encode(det_bytes(1)), "Cw==")
  assert_eq(@lib.encode(det_bytes(2)), "CzA=")
  assert_eq(@lib.encode(det_bytes(3)), "CzBV")
  assert_eq(@lib.encode(det_bytes(4)), "CzBVeg==")
  assert_eq(@lib.encode(det_bytes(5)), "CzBVep8=")
  assert_eq(@lib.encode(det_bytes(6)), "CzBVep/E")
  assert_eq(@lib.encode(det_bytes(7)), "CzBVep/E6Q==")
  // 无 padding 形态（同一批，去掉尾部 `=`）
  assert_eq(@lib.encode(det_bytes(1), padding=false), "Cw")
  assert_eq(@lib.encode(det_bytes(2), padding=false), "CzA")
  assert_eq(@lib.encode(det_bytes(4), padding=false), "CzBVeg")
  assert_eq(@lib.encode(det_bytes(7), padding=false), "CzBVep/E6Q")
  // URL-safe 对照：`\xfb\xff` → `-_8=`（RFC 4648 §5 向量，已在别处锁过，
  // 这里再钉一次是为了让「矩阵文件自带一份可独立阅读的真值」）。
  assert_eq(
    @lib.encode(b"\xfb\xff", alphabet=@lib.Alphabet::url_safe()),
    "-_8=",
  )
  assert_eq(@lib.encode(b"\xfb\xff"), "+/8=")
}
