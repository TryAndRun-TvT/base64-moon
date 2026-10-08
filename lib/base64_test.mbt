// 黑盒（包**外**）：只碰 `pub` API，锁公共契约。
//
// 【为什么错误断言要靠 `expect_*` 帮助函数】
// `pub type DecodeError = @internal.DecodeError` 只搬得动**类型名**；变体在本包
// （也就是别名的持有者）里是**只读**的，`Err(InvalidByte(4, b'!'))` 这种「构造期望值」
// 编译不过。所以期望值一律由 `base64_wbtest.mbt` 的 `expect_*` 构造好再比——
// 白盒文件在包内、能看见内核，构造点合法；黑盒文件负责锁契约。
// 实录见 [S5 §4](docs/01-规格/S5-实施裁决与M1落地.md)。

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
/// 这两条现状**已经返回 `Err`**，M1 只把它们升级成可定位的错误——
/// 不是「把漏检补上」，别把已经对的路径当成新回归。
test "decode_reports_invalid_byte_with_offset" {
  @lib.expect_invalid_byte(@lib.decode(b"Zm9v!"[:]), 4, 33)
  // `\n` 是最常见的那种「粘贴时多带了一个换行」。
  @lib.expect_invalid_byte(@lib.decode(b"Zm9vYmFy\n"[:]), 8, 10)
  // padding 出现在位置 0：它前面只可能有 0 个有效符号，一个字节至少要 2 个。
  @lib.expect_invalid_byte(@lib.decode(b"=Zm9v"[:]), 0, 61)
}

///|
/// 判据 2：末尾只剩 1 个有效符号（`len % 4 == 1`）必须被拒。
///
/// 字段是**输入总长**（crate 实测 `"AAAAZ"` → `InvalidLength(5)`），不是下标。
test "decode_rejects_one_trailing_symbol" {
  @lib.expect_invalid_length(@lib.decode(b"Z"[:]), 1)
  @lib.expect_invalid_length(@lib.decode(b"AAAAZ"[:]), 5)
}

///|
/// 判据 3：末符号的**低位冗余位非零**必须被拒。
///
/// `"Zh=="` 与 `"Zg=="` 解码出的字节相同，但 `h` 的低 4 位会被丢弃——
/// 这正是 RFC 要求二者可区分的地方（padding 之外的另一条「非规范编码」）。
test "decode_rejects_nonzero_trailing_bits" {
  @lib.expect_invalid_last_symbol(@lib.decode(b"Zh=="[:]), 1, 104)
  // `allow_trailing_bits=true` 时同一输入应放行（宽容模式，对应 WHATWG forgiving-base64）。
  assert_eq(@lib.decode(b"Zh=="[:], allow_trailing_bits=true).unwrap(), b"f")
}

///|
/// 判据 4：padding 数量 / 位置不合所选模式必须被拒。
///
/// **注意错误变体不止一种**：位置 0/1 的 padding 是 `InvalidByte`（它是「非法字节」），
/// 而数量不对是 `InvalidPadding`。
test "decode_padding_modes" {
  // RequireCanonical（默认）：`Zg` 缺 padding、`ZhA` 无 padding 都非法。
  @lib.expect_invalid_padding(@lib.decode(b"Zg"[:]))
  @lib.expect_invalid_padding(@lib.decode(b"ZhA"[:]))
  // 多余的 `=`：报**第一个** padding 的位置，而不是「最后一个多余的那个」。
  @lib.expect_invalid_byte(@lib.decode(b"Zm9vYg==="[:]), 6, 61)
  @lib.expect_invalid_byte(@lib.decode(b"Zm9vYmFy="[:]), 8, 61)
  @lib.expect_invalid_byte(@lib.decode(b"Zg==="[:]), 2, 61)
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
  @lib.expect_invalid_padding(
    @lib.decode(b"Zg=="[:], padding_mode=@lib.require_none_mode),
  )
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
  assert_eq(out[:3].to_owned().length(), 3)
  // 差一字节就是不够——`Ok` 的长度语义是「实际写入」，不是「你给了多大」。
  let small = FixedArray::make(2, b'\x00')
  @lib.expect_slice_too_small(@lib.decode_slice(b"Zm9v"[:], small))
  // 输入本身坏：**即便缓冲也不够**，仍先报输入错误（crate 实测优先级）。
  @lib.expect_decode_failed_with_invalid_byte(
    @lib.decode_slice(b"Zm9v!"[:], small),
    4,
    33,
  )
  // 而「padding 在位置 0」这条**后于**缓冲检查（crate 实测）。
  @lib.expect_slice_too_small(@lib.decode_slice(b"=Zm9v"[:], small))
}

///|
/// `encode_slice`：同上，只是错误类型里没有「输入坏」这一档。
test "encode_slice_capacity" {
  let out = FixedArray::make(8, b'\x00')
  assert_eq(@lib.encode_slice(b"foobar"[:], out), Ok(8))
  assert_eq(out[:8].to_owned().length(), 8)
  let small = FixedArray::make(7, b'\x00')
  @lib.expect_encode_too_small(@lib.encode_slice(b"foobar"[:], small))
  assert_eq(@lib.encode_slice(b""[:], FixedArray::make(0, b'\x00')), Ok(0))
  // `padding=false` 时「够不够」按无 padding 的目标长度判。
  let nopad = FixedArray::make(6, b'\x00')
  assert_eq(@lib.encode_slice(b"foob"[:], nopad, padding=false), Ok(6))
  // 恰好够：`padding=false` 不写 `=`，故 6 字节缓冲存得下 6 个符号。
  @lib.expect_encode_too_small(
    @lib.encode_slice(b"foob"[:], FixedArray::make(5, b'\x00')),
  )
}

///|
/// 便利形态：`String` 入参（非主入口）。
test "decode_string_convenience" {
  assert_eq(@lib.decode_string("Zm9vYmFy").unwrap(), b"foobar")
  @lib.expect_invalid_byte(@lib.decode_string("Zm9v!"), 4, 33)
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
  @lib.expect_invalid_byte(@lib.decode(b"Zm9v!"[:]), 4, 33)
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
