// lib/ —— **公共 API 外壳**（facade）。
//
// 本包（lib/facade.mbt）是唯一对使用者可见的层：它把内核（lib/internal/）的
// 零分配接口**物化**成好用的 `Bytes` 形态，并持有默认配置。
//
// 分层纪律（见 AGENTS.md §二.1 与
// docs/01-规格/S1-rust-base64-移植可行性分析.md §9）：
//   · 符号表 / padding / 错误语义一律在 lib/internal/ 落地，本层**不重复实现**；
//   · 本层可以 import lib/internal/*，internal **不得**反向 import 本层；
//   · `decode` 的入参落在**字节视图**上（非 `String`），理由见 S1 §5.3。
//
// 错误类型的对外形态见 docs/01-规格/S5-实施裁决与M1落地.md §4：
// 用 `pub type X = @internal.X` 把内核类型**重命名**到本包。

///|
/// Base64 字母表变体（RFC 4648）；由 `standard()` / `url_safe()` 取用。
pub enum Alphabet {
  /// 标准字母表（`+` / `/`）
  Standard
  /// URL-safe 字母表（`-` / `_`）
  UrlSafe
}

///|
/// 标准字母表（`+` / `/`）。
pub fn Alphabet::standard() -> Alphabet {
  Standard
}

///|
/// URL 安全字母表（`-` / `_`）。
pub fn Alphabet::url_safe() -> Alphabet {
  UrlSafe
}

///|
/// 解码错误：**重命名**内核的 `DecodeError` 到本包。
///
/// 变体名跨包可用（调用方写 `Err(InvalidByte(4, b'!'))`，无需包限定）。
/// 但**构造点只在 `lib/internal`**：MoonBit 的枚举对其它包只读，
/// 本层只做类型重命名与错误透传，不新造错误值。
///
/// 用法（M1 起）：调用方 `match` 时**不写包限定**——
///
/// ```
/// match @lib.decode(b"Zm9v!"[:]) {
///   Ok(bytes) => ...
///   Err(InvalidByte(offset, byte)) => ...
///   Err(InvalidLength(len)) => ...
///   Err(InvalidLastSymbol(offset, symbol)) => ...
///   Err(InvalidPadding) => ...
/// }
/// ```
///
/// 为什么不是「re-export 变体」：MoonBit 无此语法（`pub typealias` 不存在），
/// 而 `pub type DecodeError = @internal.DecodeError` 只搬得动**类型名**、
/// 搬不动变体限定名 `@lib.InvalidByte`。不写限定反而可用——前提是本包对外
/// 暴露了该类型的**具体值**（`decode` 就返回它），类型推导会把变体一并解析。
/// 实录见 [S5 §4](docs/01-规格/S5-实施裁决与M1落地.md)。
pub type DecodeError = @internal.DecodeError

///|
/// `decode_slice` 的错误：区分「输入解不出来」与「你的缓冲太小」。
pub type DecodeSliceError = @internal.DecodeSliceError

///|
/// `encode_slice` 的错误。
pub type EncodeSliceError = @internal.EncodeSliceError

///|
/// 解码时对 `=` 填充的检查强度。
///
/// 用 `pub type` 重命名内核的同名枚举。**变体在 `lib/internal` 构造**——
/// MoonBit 的枚举对其它包是只读的（`Cannot create values of the read-only type`），
/// 所以「三态各一个具名构造器」不是审美选择，是唯一能跨包构造的形态。
pub type DecodePaddingMode = @internal.DecodePaddingMode

///|
/// 有无 padding 都接受（缺 padding 容忍；多余 `=` 仍非法）。
pub let indifferent_mode : DecodePaddingMode = @internal.DecodePaddingMode::indifferent()

///|
/// 必须恰好是规范 padding：`(padding 数 + 有效符号数) % 4 == 0`。**这是默认值。**
///
/// > 默认值是实测的，不是选的：crate `GeneralPurposeConfig::new()` 即此
/// > （[S5 §2.1](docs/01-规格/S5-实施裁决与M1落地.md)）。
pub let require_canonical_mode : DecodePaddingMode = @internal.DecodePaddingMode::require_canonical()

///|
/// 必须完全没有 padding。
pub let require_none_mode : DecodePaddingMode = @internal.DecodePaddingMode::require_none()

///|
/// 取字母表对应的内核字母表值。
fn alphabet_of(alphabet : Alphabet) -> @internal.Alphabet {
  match alphabet {
    Standard => @internal.Alphabet::standard()
    UrlSafe => @internal.Alphabet::url_safe()
  }
}

///|
/// 按配置构造内核引擎。
///
/// > **明账（已实测结清）**：每次调用建 64 + 256 = 320 项表，约 360 ns，
/// > 占外壳编码的 75.5%（0 B）/ 66.0%（3 B）/ 2.2%（1024 B）。
/// > 换成顶层常量引擎的真实收益只有 **3.9%（1024 B，噪声内）**，
/// > 故**刻意不做**：为噪声级收益把「纯函数外壳」改成模块级共享 `FixedArray`
/// > （引用语义，只读是约定而非类型保证）不划算——`Alphabet::url_safe()`
/// > 少一次 `copy()` 就会污染标准表，这类坑本仓踩过。
/// > 实测与裁决见 [S6 §1–§2](docs/01-规格/S6-性能实测与M3裁决.md)，复跑见 S6 §6.1。
/// > 需要吞吐的调用方应改用 `encode_slice` / `decode_slice` 自持缓冲，而不是靠这里省常数项。
fn engine(
  alphabet : Alphabet,
  padding : Bool,
  padding_mode : DecodePaddingMode,
  allow_trailing_bits : Bool,
) -> @internal.Engine {
  @internal.Engine::new(
    alphabet_of(alphabet),
    @internal.Config::new(padding, allow_trailing_bits, padding_mode),
  )
}

///|
/// 把字节数组编码为 Base64 字符串。
///
/// `padding=false` 是 URL-safe 场景的惯例形态（RFC 4648 §5 允许省略 `=`）。
///
/// ```
/// @lib.encode(b"foob")                    // "Zm9vYg=="
/// @lib.encode(b"foob", padding=false)     // "Zm9vYg"
/// ```
pub fn encode(
  data : Bytes,
  alphabet? : Alphabet = Standard,
  padding? : Bool = true,
) -> String {
  let engine = engine(alphabet, padding, require_canonical_mode, false)
  let view = data[:]
  let cap = @internal.encoded_len(view)
  let out = FixedArray::make(cap, b'\x00')
  // 内核只写有效符号，padding 由 `add_padding` 单点补——见 S4 §2.1。
  let written = @internal.encode_into(engine, view, out)
  let total = if padding {
    written + @internal.add_padding(written, engine.alphabet.padding, out)
  } else {
    written
  }
  let sb = StringBuilder()
  for i = 0; i < total; i = i + 1 {
    sb.write_char(out[i].to_int().unsafe_to_char())
  }
  sb.to_string()
}

///|
/// 把字节数组编码写入调用方给定的定长缓冲，返回**写入的字节数**。
///
/// 这是**唯一**能避开输出二次拷贝的形态，对齐 crate 的 `encode_slice(&mut [u8]) -> usize`。
/// 缓冲不足返回 `Err(OutputSliceTooSmall)`——`encode` 内部即按 `encoded_len` 分配，
/// 永远不会撞上这条。
pub fn encode_slice(
  data : BytesView,
  out : FixedArray[Byte],
  alphabet? : Alphabet = Standard,
  padding? : Bool = true,
) -> Result[Int, EncodeSliceError] {
  // 内核不写 padding，故「够不够」要按**含 padding 的目标长度**判。
  let need = if padding {
    @internal.encoded_len(data)
  } else {
    let rem = data.length() % 3
    data.length() / 3 * 4 +
    (if rem == 1 { 2 } else if rem == 2 { 3 } else { 0 })
  }
  if out.length() < need {
    return Err(@internal.EncodeSliceError::output_slice_too_small())
  }
  let engine = engine(alphabet, padding, require_canonical_mode, false)
  let written = @internal.encode_into(engine, data, out)
  if padding {
    Ok(written + @internal.add_padding(written, engine.alphabet.padding, out))
  } else {
    Ok(written)
  }
}

///|
/// 解码 Base64 **字节视图**为字节数组。
///
/// 入参是字节视图而**不是** `String`：`String` 是 UTF-16，拿它当字节源是错的前提
/// （[S1 §5.3](docs/01-规格/S1-rust-base64-移植可行性分析.md)）。
/// 便利形态见 `decode_string`。
///
/// ```
/// @lib.decode(b"Zm9vYmFy"[:])             // Ok(b"foobar")
/// @lib.decode(b"Zg"[:])                   // Err(InvalidPadding) —— 默认 RequireCanonical
/// @lib.decode(b"Zg"[:], padding_mode=Indifferent)  // Ok(b"f")
/// ```
pub fn decode(
  input : BytesView,
  alphabet? : Alphabet = Standard,
  padding_mode? : DecodePaddingMode = require_canonical_mode,
  allow_trailing_bits? : Bool = false,
) -> Result[Bytes, DecodeError] {
  let engine = engine(alphabet, true, padding_mode, allow_trailing_bits)
  let out = FixedArray::make(
    @internal.decoded_len_estimate(input.length()),
    b'\x00',
  )
  match @internal.decode_into(engine, input, out) {
    Ok(len) => Ok(Bytes::from_array(out[:len]))
    Err(DecodeFailed(e)) => Err(e)
    // 缓冲按估算值分配，必然够——crate 在这里也是 unreachable。
    // 真要说到这一步，唯一的可能是长度估算与实际不符；用 `InvalidLength` 兜住，
    // 不静默返回「部分解码结果」。
    Err(OutputSliceTooSmall) =>
      Err(@internal.decode_error_invalid_length(input.length()))
  }
}

///|
/// 解码 Base64 **字节视图**写入调用方给定的定长缓冲，返回**写入的字节数**。
///
/// 对齐 crate 的 `decode_slice`。返回的 `DecodeSliceError` 区分「输入坏」与
/// 「缓冲小」——**混在一起会让调用方分不清该改数据还是该放大缓冲**。
///
/// 错误优先级照 crate（[S5 §3](docs/01-规格/S5-实施裁决与M1落地.md)）：
/// 尾部 `rem == 1` 的便利检查与完整 4 元组的非法字节**先于**缓冲检查，
/// 而「padding 出现在位置 0/1」**后于**缓冲检查。
pub fn decode_slice(
  input : BytesView,
  out : FixedArray[Byte],
  alphabet? : Alphabet = Standard,
  padding_mode? : DecodePaddingMode = require_canonical_mode,
  allow_trailing_bits? : Bool = false,
) -> Result[Int, DecodeSliceError] {
  let engine = engine(alphabet, true, padding_mode, allow_trailing_bits)
  @internal.decode_into(engine, input, out)
}

///|
/// `decode` 的**便利形态**：收 `String`（按 ASCII 身份转字节视图），**非主入口**。
///
/// 只对「本来就是 ASCII 的 base64 文本」成立。含非 ASCII 字符的 `String` 会先按
/// UTF-8 编码再解码——对那些输入，主入口 `decode` 才是对的。
pub fn decode_string(
  text : String,
  alphabet? : Alphabet = Standard,
  padding_mode? : DecodePaddingMode = require_canonical_mode,
  allow_trailing_bits? : Bool = false,
) -> Result[Bytes, DecodeError] {
  decode(@utf8.encode(text)[:], alphabet~, padding_mode~, allow_trailing_bits~)
}

///|
/// `Alphabet::UrlSafe` 与 `Alphabet::Standard` 只在 `+ / -`、`/ / _` 上不同。
pub fn Alphabet::is_url_safe(self : Alphabet) -> Bool {
  match self {
    Standard => false
    UrlSafe => true
  }
}

// ── 期望值构造器（供黑盒测试 `base64_test.mbt` 用） ──────────────────────────
//
// 为什么需要这一层：`pub type DecodeError = @internal.DecodeError` 只搬类型名，
// **变体在本包只读**（`Cannot create values of the read-only type`）。
// 于是本包里的测试写不出 `Err(InvalidByte(4, b'!'))` 这种「期望值」。
//
// 出路有两条，都实测过：
//   · 定义包补一组具名构造器（`@internal.InvalidByte(4, b'!')`）——但那是把内部
//     构造面扩成公共 API，只为测试服务，不该进对外契约；
//   · **把比对留在本层**：调用方只给「我期望什么形状」，构造与比较都在本层做。
//     后者不扩公共面，故采用。第三方包（用户代码）本可直接写变体名，
//     这一层只是补上「持有别名的包」这个盲区。

///|
/// 把解码错误渲染成一句可读的话，例：`InvalidByte(offset=4, byte=0x21)`。
///
/// 存在的理由与 `expect_*` 同：变体名在包外**不得**裸写（需要 import
/// `lib/internal`，而 internal 包不可被外部 import）。宿主想展示错误时走这里，
/// 不必自己 import internal 包。需要**编程式**拿到 offset 的场景见
/// [S5 §4](docs/01-规格/S5-实施裁决与M1落地.md) 的取舍说明。
pub fn describe(e : DecodeError) -> String {
  @internal.describe_decode_error(e)
}

///|
/// 把 `decode_slice` 的结果渲染成一句可读的话（宿主/调试用）。
pub fn describe_slice_result(r : Result[Int, DecodeSliceError]) -> String {
  match r {
    Ok(n) => "Ok(" + n.to_string() + ")"
    Err(e) =>
      match e {
        DecodeFailed(inner) =>
          "DecodeFailed(" + @internal.describe_decode_error(inner) + ")"
        OutputSliceTooSmall => "OutputSliceTooSmall"
      }
  }
}

///|
/// 断言解码**成功**且结果等于 `expected`。
///
/// 为什么不直接 `assert_eq(@lib.decode(..), Ok(bytes))`：那个断言要求
/// `Result[_, DecodeError]` 实现 `Eq` / `Debug`，而这两个 impl 由 `lib/internal`
/// 提供——调用方**不得** import internal 包（internal 可见性规则），
/// 于是这条最自然的写法在包外编译不过。本函数把比较留在 `lib` 内。
pub fn expect_decoded(
  actual : Result[Bytes, DecodeError],
  expected : Bytes,
) -> Unit {
  match actual {
    Ok(bytes) =>
      if bytes.length() != expected.length() {
        abort(
          "解码长度不符：实际 \{bytes.length()}，期望 \{expected.length()}",
        )
      } else {
        for i = 0; i < expected.length(); i = i + 1 {
          if bytes[i] != expected[i] {
            abort("解码第 \{i} 字节不符")
          }
        }
      }
    Err(_) => abort("期望解码成功，实际 Err(..)")
  }
}

///|
/// 断言解码结果是一个 `InvalidByte(offset, byte)`。
///
/// `offset` 是 0 基下标，`byte` 是出错字节的码点（如 `b'!'` 写 33）。
pub fn expect_invalid_byte(
  actual : Result[Bytes, DecodeError],
  offset : Int,
  byte : Int,
) -> Unit raise {
  expect_decode_error(
    actual,
    @internal.decode_error_invalid_byte(offset, byte.to_byte()),
  )
}

///|
/// 断言解码结果是 `InvalidLength(输入总长)`（字段是**总长**，不是下标）。
pub fn expect_invalid_length(
  actual : Result[Bytes, DecodeError],
  length : Int,
) -> Unit raise {
  expect_decode_error(actual, @internal.decode_error_invalid_length(length))
}

///|
/// 断言解码结果是 `InvalidLastSymbol(offset, symbol)`。
pub fn expect_invalid_last_symbol(
  actual : Result[Bytes, DecodeError],
  offset : Int,
  symbol : Int,
) -> Unit raise {
  expect_decode_error(
    actual,
    @internal.decode_error_invalid_last_symbol(offset, symbol.to_byte()),
  )
}

///|
/// 断言解码结果是 `InvalidPadding`。
pub fn expect_invalid_padding(
  actual : Result[Bytes, DecodeError],
) -> Unit raise {
  expect_decode_error(actual, @internal.DecodeError::invalid_padding())
}

///|
/// 断言 `decode_slice` 报「缓冲太小」。
pub fn expect_slice_too_small(actual : Result[Int, DecodeSliceError]) -> Unit {
  match actual {
    Ok(n) => abort("期望 OutputSliceTooSmall，实际 Ok(\{n})")
    Err(DecodeFailed(_)) =>
      abort("期望 OutputSliceTooSmall，实际 DecodeFailed(..)")
    Err(OutputSliceTooSmall) => ()
  }
}

///|
/// 断言 `decode_slice` 报指定的解码错误（而不是「缓冲太小」）。
///
/// 这条断言存在的理由就是**优先级**：crate 实测「非法字节」先于「缓冲不足」，
/// 而「padding 在位置 0/1」后于它。写错次序时它会红。
pub fn expect_decode_failed_with_invalid_byte(
  actual : Result[Int, DecodeSliceError],
  offset : Int,
  byte : Int,
) -> Unit raise {
  match actual {
    Ok(n) => abort("期望 DecodeFailed，实际 Ok(\{n})")
    Err(OutputSliceTooSmall) =>
      abort("期望 DecodeFailed，实际 OutputSliceTooSmall")
    Err(DecodeFailed(e)) =>
      assert_eq(e, @internal.decode_error_invalid_byte(offset, byte.to_byte()))
  }
}

///|
/// 断言 `encode_slice` 报「缓冲太小」。
pub fn expect_encode_too_small(actual : Result[Int, EncodeSliceError]) -> Unit {
  match actual {
    Ok(n) => abort("期望 OutputSliceTooSmall，实际 Ok(\{n})")
    Err(OutputSliceTooSmall) => ()
  }
}

///|
/// 统一的「解码错误相等」断言：失败信息带上实际值，便于定位。
fn expect_decode_error(
  actual : Result[Bytes, DecodeError],
  expected : DecodeError,
) -> Unit raise {
  match actual {
    Ok(bytes) =>
      abort(
        "期望与失败不符：实际 Ok(\{bytes.length()} 字节)，期望 Err(..)",
      )
    Err(e) => assert_eq(e, expected)
  }
}
