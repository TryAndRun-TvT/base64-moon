// 黑盒（包**外**）：只碰 `pub` API，锁公共契约。
//
// 【这一层与白盒的分工】`*_test.mbt` 编译在包外，只能看见 `pub` 面——
// 于是它天然回答「用户拿到的行为对不对」。错误变体的构造点在
// `lib/internal/error_contract_wbtest.mbt`（定义包 = 唯一可构造处），
// 本文件按**形状**断言（`InvalidByte(offset, byte)` 的模式匹配）。
//
// 【为什么不能在这里 `assert_eq` 整个 `Result`】`Result[_, DecodeError]` 的
// `Eq` / `Debug` impl 由 `lib/internal` 提供，而**外部包不得 import internal**
// （internal 可见性规则）。故这里的两种可用形态是：模式匹配（下例）或用
// `moonbitlang/core/debug` 的 `@debug.to_string`（见 `decode_errors_are_showable`）。

///|
/// 把 `Err(e)` 渲染成展示串；`Ok` 渲染成 `Ok`。
/// 只为本文件服务（`fn` 在 `*_test.mbt` 里是包外私有，不进 `.mbti`）。
fn err_repr(r : Result[Bytes, @lib.DecodeError]) -> String {
  match r {
    Ok(_) => "Ok"
    Err(e) => Repr(e).to_string()
  }
}

///|
test "encode_standard_padding_forms" {
  // RFC 4648 §10：三种余数的标准测试向量
  assert_eq(@lib.encode(b"f"), "Zg==")
  assert_eq(@lib.encode(b"fo"), "Zm8=")
  assert_eq(@lib.encode(b"foo"), "Zm9v")
  assert_eq(@lib.encode(b"foob"), "Zm9vYg==")
  assert_eq(@lib.encode(b"fooba"), "Zm9vYmE=")
  assert_eq(@lib.encode(b"foobar"), "Zm9vYmFy")
}

///|
test "encode_without_padding" {
  // URL-safe 场景惯例省略 `=`；带不带 padding 输出长度与内容都不同。
  assert_eq(@lib.encode(b"f", padding=false), "Zg")
  assert_eq(@lib.encode(b"fo", padding=false), "Zm8")
  assert_eq(@lib.encode(b"foob", padding=false), "Zm9vYg")
  assert_eq(@lib.encode(b"foobar", padding=false), "Zm9vYmFy")
  assert_eq(@lib.encode(b""), "")
  assert_eq(@lib.encode(b"", padding=false), "")
}

///|
test "encode_urlsafe_uses_alt_chars" {
  // URL-safe 字母表把 `+` / `/` 换成 `-` / `_`（RFC 4648 §5 向量）
  assert_eq(
    @lib.encode(b"\xfb\xff", alphabet=@lib.Alphabet::url_safe()),
    "-_8=",
  )
  assert_eq(@lib.encode(b"\xfb\xff"), "+/8=")
  assert_eq(
    @lib.encode(b"\xfb\xff", alphabet=@lib.Alphabet::url_safe(), padding=false),
    "-_8",
  )
}

///|
test "decode_round_trips" {
  assert_eq(@lib.decode(b"Zm9vYmFy"[:]).unwrap(), b"foobar")
  // 默认 RequireCanonical：末尾整组可以不带 padding（`Zm9vYmFy=` 反而非法）。
  assert_eq(@lib.decode(b"Zg=="[:]).unwrap(), b"f")
  assert_eq(@lib.decode(b"Zm9vYmE="[:]).unwrap(), b"fooba")
  assert_eq(@lib.decode(b""[:]).unwrap(), b"")
  assert_eq(
    @lib.decode(b"-_8="[:], alphabet=@lib.Alphabet::url_safe()).unwrap(),
    b"\xfb\xff",
  )
}

///|
/// 判据 1：非法字节必须报出**带 offset 的结构化错误**。
///
/// `\n` 是最常见的那种「粘贴时多带了一个换行」；`=` 在位置 0 也是
/// `InvalidByte`（它是「非法字节」，不是「填充数量不对」）。
test "decode_reports_invalid_byte_with_offset" {
  match @lib.decode(b"Zm9v!"[:]) {
    Err(InvalidByte(offset, byte)) => {
      assert_eq(offset, 4)
      assert_eq(byte, b'!')
    }
    other => fail("期望 InvalidByte(4, '!')，实际 \{err_repr(other)}")
  }
  match @lib.decode(b"Zm9vYmFy\n"[:]) {
    Err(InvalidByte(offset, byte)) => {
      assert_eq(offset, 8)
      assert_eq(byte, b'\n')
    }
    other => fail("期望 InvalidByte(8, '\\n')，实际 \{err_repr(other)}")
  }
  match @lib.decode(b"=Zm9v"[:]) {
    Err(InvalidByte(offset, byte)) => {
      assert_eq(offset, 0)
      assert_eq(byte, b'=')
    }
    other => fail("期望 InvalidByte(0, '=')，实际 \{err_repr(other)}")
  }
}

///|
/// 判据 2：末尾只剩 1 个有效符号（`len % 4 == 1`）必须被拒。
///
/// 字段是**输入总长**（crate 实测 `"AAAAZ"` → `InvalidLength(5)`），不是下标。
test "decode_rejects_one_trailing_symbol" {
  match @lib.decode(b"Z"[:]) {
    Err(InvalidLength(length)) => assert_eq(length, 1)
    other => fail("期望 InvalidLength(1)，实际 \{err_repr(other)}")
  }
  match @lib.decode(b"AAAAZ"[:]) {
    Err(InvalidLength(length)) => assert_eq(length, 5)
    other => fail("期望 InvalidLength(5)，实际 \{err_repr(other)}")
  }
}

///|
/// 判据 3：末符号的**低位冗余位非零**必须被拒，且报的是**末符号自己的下标**。
///
/// `"Zh=="` 与 `"Zg=="` 解码出的字节相同，但 `h` 的低 4 位会被丢弃——
/// 这正是 RFC 要求二者可区分的地方（padding 之外的另一条「非规范编码」）。
test "decode_rejects_nonzero_trailing_bits" {
  match @lib.decode(b"Zh=="[:]) {
    Err(InvalidLastSymbol(offset, symbol)) => {
      assert_eq(offset, 1)
      assert_eq(symbol, b'h')
    }
    other =>
      fail("期望 InvalidLastSymbol(1, 'h')，实际 \{err_repr(other)}")
  }
  // `allow_trailing_bits=true` 时同一输入应放行（宽容模式，对应 WHATWG forgiving-base64）。
  assert_eq(@lib.decode(b"Zh=="[:], allow_trailing_bits=true).unwrap(), b"f")
}

///|
/// 判据 4：padding 数量 / 位置不合所选模式必须被拒。
///
/// **注意错误变体不止一种**：位置 0/1 的 padding 是 `InvalidByte`（它是「非法字节」），
/// 而数量不对是 `InvalidPadding`。
test "decode_padding_modes" {
  // RequireCanonical（默认）：`Zg` 缺 padding、`ZhA` 多出一个符号都非法。
  match @lib.decode(b"Zg"[:]) {
    Err(InvalidPadding) => ()
    other => fail("期望 InvalidPadding，实际 \{err_repr(other)}")
  }
  match @lib.decode(b"ZhA"[:]) {
    Err(InvalidPadding) => ()
    other => fail("期望 InvalidPadding，实际 \{err_repr(other)}")
  }
  // 多余的 `=`：报**第一个** padding 的位置，而不是「最后一个多余的那个」。
  match @lib.decode(b"Zm9vYg==="[:]) {
    Err(InvalidByte(offset, byte)) => {
      assert_eq(offset, 6)
      assert_eq(byte, b'=')
    }
    other => fail("期望 InvalidByte(6, '=')，实际 \{err_repr(other)}")
  }
  match @lib.decode(b"Zm9vYmFy="[:]) {
    Err(InvalidByte(offset, byte)) => {
      assert_eq(offset, 8)
      assert_eq(byte, b'=')
    }
    other => fail("期望 InvalidByte(8, '=')，实际 \{err_repr(other)}")
  }
  match @lib.decode(b"Zg==="[:]) {
    Err(InvalidByte(offset, byte)) => {
      assert_eq(offset, 2)
      assert_eq(byte, b'=')
    }
    other => fail("期望 InvalidByte(2, '=')，实际 \{err_repr(other)}")
  }
  // padding 落在本 4 元组的**位置 1**：`"A=AA"` 的第一个符号后面就跟了 `=`。
  // 一个字节至少要 2 个符号，故这里必然非法，且报**这个 padding 自己的下标 1**。
  // 这条单列，是因为上面三条都只在**位置 0** 或「padding 之后又出现符号」上：
  // 把 `idx - start < 2` 放宽成 `< 1`，它们全绿而本输入被静默解成 3 字节。
  match @lib.decode(b"A=AA"[:]) {
    Err(InvalidByte(offset, byte)) => {
      assert_eq(offset, 1)
      assert_eq(byte, b'=')
    }
    other => fail("期望 InvalidByte(1, '=')，实际 \{err_repr(other)}")
  }
  // padding 之后**又出现有效符号**：`"AA=A"` 末尾那个 `A` 落在 padding 后面。
  // 必须报**第一个** padding 的位置（下标 2），而不是「好像解出了东西」。
  // 这条单列的理由同上：把「padding 之后不许再有符号」删掉，
  // `"AA=A"` 会被静默解成 2 字节，而上面所有用例仍然全绿。
  match @lib.decode(b"AA=A"[:]) {
    Err(InvalidByte(offset, byte)) => {
      assert_eq(offset, 2)
      assert_eq(byte, b'=')
    }
    other => fail("期望 InvalidByte(2, '=')，实际 \{err_repr(other)}")
  }
  // 同一判据的另一格：位置 2 与 3 是 padding 时**合法**（`"AA=="`），
  // 故上面的 `< 2` 不能放宽成 `< 3`。
  assert_eq(@lib.decode(b"AA=="[:]).unwrap(), b"\x00")
  // Indifferent：缺 padding 也接受。
  assert_eq(
    @lib.decode(b"Zg"[:], padding_mode=@lib.indifferent_mode).unwrap(),
    b"f",
  )
  assert_eq(
    @lib.decode(b"ZhA"[:], padding_mode=@lib.indifferent_mode).unwrap(),
    b"f\x10",
  )
  // RequireNone：出现任何 padding 都是 `InvalidPadding`。
  match @lib.decode(b"Zg=="[:], padding_mode=@lib.require_none_mode) {
    Err(InvalidPadding) => ()
    other => fail("期望 InvalidPadding，实际 \{err_repr(other)}")
  }
  assert_eq(
    @lib.decode(b"Zg"[:], padding_mode=@lib.require_none_mode).unwrap(),
    b"f",
  )
}

///|
/// `decode_slice`：定长输出形态 + 「输入坏」与「缓冲小」是两件事。
test "decode_slice_distinguishes_input_from_capacity" {
  let out = FixedArray::make(3, b'\x00')
  assert_eq(@lib.decode_slice(b"Zm9v"[:], out), Ok(3))
  assert_eq(Bytes::from_array(out[:3]), b"foo")
  // 差一字节就是不够——`Ok` 的长度语义是「实际写入」，不是「你给了多大」。
  let small = FixedArray::make(2, b'\x00')
  match @lib.decode_slice(b"Zm9v"[:], small) {
    Err(OutputSliceTooSmall) => ()
    _ => fail("期望 OutputSliceTooSmall")
  }
  // 输入本身坏：**即便缓冲也不够**，仍先报输入错误（crate 实测优先级）。
  match @lib.decode_slice(b"Zm9v!"[:], small) {
    Err(DecodeFailed(InvalidByte(offset, byte))) => {
      assert_eq(offset, 4)
      assert_eq(byte, b'!')
    }
    _ => fail("期望 DecodeFailed(InvalidByte(4, '!'))")
  }
  // 而「padding 在位置 0」这条**后于**缓冲检查（crate 实测）。
  match @lib.decode_slice(b"=Zm9v"[:], small) {
    Err(OutputSliceTooSmall) => ()
    _ =>
      fail(
        "期望 OutputSliceTooSmall（位置 0 的 padding 检查后于缓冲检查）",
      )
  }
}

///|
/// `encode_slice`：同上，只是错误类型里没有「输入坏」这一档。
test "encode_slice_capacity" {
  let out = FixedArray::make(8, b'\x00')
  assert_eq(@lib.encode_slice(b"foobar"[:], out), Ok(8))
  assert_eq(Bytes::from_array(out[:8]), b"Zm9vYmFy")
  let small = FixedArray::make(7, b'\x00')
  match @lib.encode_slice(b"foobar"[:], small) {
    Err(OutputSliceTooSmall) => ()
    _ => fail("期望 OutputSliceTooSmall")
  }
  assert_eq(@lib.encode_slice(b""[:], FixedArray::make(0, b'\x00')), Ok(0))
  // `padding=false` 时「够不够」按无 padding 的目标长度判：6 字节缓冲存得下 6 个符号。
  let nopad = FixedArray::make(6, b'\x00')
  assert_eq(@lib.encode_slice(b"foob"[:], nopad, padding=false), Ok(6))
  assert_eq(Bytes::from_array(nopad[:6]), b"Zm9vYg")
  // 恰好差一字节即失败
  match @lib.encode_slice(b"foob"[:], FixedArray::make(5, b'\x00')) {
    Err(OutputSliceTooSmall) => ()
    _ => fail("期望 OutputSliceTooSmall（padding=false 时 5 < 6）")
  }
  // padding=true 时同一输入要 8 字节：目标长度按含 `=` 算，不是按有效符号算。
  match @lib.encode_slice(b"foob"[:], FixedArray::make(7, b'\x00')) {
    Err(OutputSliceTooSmall) => ()
    _ => fail("期望 OutputSliceTooSmall（padding=true 时 7 < 8）")
  }
}

///|
/// 便利形态：`String` 入参（非主入口）。
test "decode_string_convenience" {
  assert_eq(@lib.decode_string("Zm9vYmFy").unwrap(), b"foobar")
  // 非 ASCII 的 `String` 会先按 UTF-8 编码再解码，于是首字节就非法。
  match @lib.decode_string("Zm9v!") {
    Err(InvalidByte(offset, byte)) => {
      assert_eq(offset, 4)
      assert_eq(byte, b'!')
    }
    other => fail("期望 InvalidByte(4, '!')，实际 \{err_repr(other)}")
  }
}

///|
/// 错误是**结构化**的，同时也能被展示：`describe` 给出可读串，
/// 而 `Debug`（core 的 `to_repr`）给出变体形态。
test "decode_errors_are_showable" {
  // `describe`：给人看的一种稳定口径（`describe` 是 `lib` 的公共 API，可被依赖）
  assert_eq(
    @lib.describe(@lib.decode(b"Zm9v!"[:]).unwrap_err()),
    "InvalidByte(offset=4, byte=0x21)",
  )
  assert_eq(
    @lib.describe(@lib.decode(b"Zh=="[:]).unwrap_err()),
    "InvalidLastSymbol(offset=1, symbol=0x68)",
  )
  assert_eq(
    @lib.describe(
      @lib.decode(b"Zg=="[:], padding_mode=@lib.require_none_mode).unwrap_err(),
    ),
    "InvalidPadding",
  )
  // `Repr` 走 core 的 `Debug` impl（由内核包的 `extend` 显式登记）。
  // **格式不属契约**——它由 core 决定，这里只钉「形态可读、字段在」，
  // 不逐字符钉死，避免把 core 的展示格式当成本库的承诺。
  assert_eq(err_repr(@lib.decode(b"Z"[:])), "InvalidLength(1)")
  assert_eq(err_repr(@lib.decode(b"Zm9v!"[:])), "InvalidByte(4, 0x21)")
  // 结果类型也能展示：`Err(..)` 的形态由 core 决定，内核只负责内层可 Debug。
  assert_eq(
    Repr(@lib.decode_slice(b"Zm9v"[:], FixedArray::make(1, b'\x00'))).to_string(),
    "Err(OutputSliceTooSmall)",
  )
  assert_eq(
    Repr(@lib.encode_slice(b"foobar"[:], FixedArray::make(1, b'\x00'))).to_string(),
    "Err(OutputSliceTooSmall)",
  )
  assert_eq(
    @lib.describe_slice_result(
      @lib.decode_slice(b"Zm9v"[:], FixedArray::make(2, b'\x00')),
    ),
    "OutputSliceTooSmall",
  )
  assert_eq(
    @lib.describe_slice_result(
      @lib.decode_slice(b"Zm9v"[:], FixedArray::make(3, b'\x00')),
    ),
    "Ok(3)",
  )
  assert_eq(
    @lib.describe_slice_result(
      @lib.decode_slice(b"Zm9v!"[:], FixedArray::make(3, b'\x00')),
    ),
    "DecodeFailed(InvalidByte(offset=4, byte=0x21))",
  )
}

///|
/// 字母表变体的取值与判定。
test "alphabet_variants" {
  assert_eq(@lib.Alphabet::standard().is_url_safe(), false)
  assert_eq(@lib.Alphabet::url_safe().is_url_safe(), true)
}

///|
/// `Alphabet::is_url_safe`：字母表变体开关的谓词，与 `encode` 的取值一致。
///
/// 这条是**公共契约**（`.mbti` 可见），此前无任何断言——补上，免得它悄悄写反。
test "alphabet_is_url_safe_predicate" {
  assert_eq(@lib.Alphabet::standard().is_url_safe(), false)
  assert_eq(@lib.Alphabet::url_safe().is_url_safe(), true)
}

///|
/// `describe` / `describe_slice_result`：把结构化错误渲染成可读串（宿主的展示入口）。
///
/// 这两条此前无断言。它们的价值正是「**包外**不 import internal 也能展示错误」，
/// 故断言直接钉在**产出串**上——字段值若丢，串就对不上。
test "describe_renderers_for_host_display" {
  // 错误按**形状**断言（变体字段），不靠 `expect_*` 辅助——公共面已无此类符号。
  match @lib.decode(b"Zm9v!"[:]) {
    Err(InvalidByte(offset, byte)) => {
      assert_eq(offset, 4)
      assert_eq(byte, b'!')
    }
    _ => abort("`Zm9v!` 应以 InvalidByte(4, b'!') 拒绝")
  }
  assert_eq(
    @lib.describe(@lib.decode(b"Zm9v!"[:]).unwrap_err()),
    "InvalidByte(offset=4, byte=0x21)",
  )
  assert_eq(
    @lib.describe_slice_result(
      @lib.decode_slice(b"Zm9v"[:], FixedArray::make(3, b'\x00')),
    ),
    "Ok(3)",
  )
  assert_eq(
    @lib.describe_slice_result(
      @lib.decode_slice(b"Zm9v"[:], FixedArray::make(2, b'\x00')),
    ),
    "OutputSliceTooSmall",
  )
  assert_eq(
    @lib.describe_slice_result(
      @lib.decode_slice(b"Zm9v!"[:], FixedArray::make(2, b'\x00')),
    ),
    "DecodeFailed(InvalidByte(offset=4, byte=0x21))",
  )
}
