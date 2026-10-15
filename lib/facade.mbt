// lib/ —— **公共 API 外壳**（facade）。
//
// 本层是唯一对使用者可见的层：把内核（lib/internal/）的零分配接口
// **物化**成好用的 `Bytes` 形态，并持有默认配置。
//
// 分层纪律（AGENTS.md §二.1）：
//   · 符号表 / padding / 错误语义一律在 lib/internal/ 落地，本层**不重复实现**；
//   · 本层可以 import lib/internal/*，internal **不得**反向 import 本层；
//   · `decode` 的入参落在**字节视图**上（非 `String`）——`String` 是 UTF-16，
//     拿它当字节源是错的前提（[S1 §5.3](docs/01-规格/S1-rust-base64-移植可行性分析.md)）。
//
// 错误类型的对外形态：`pub type X = @internal.X`，只搬**类型名**。
// 本层不提供 `expect_*` 一类的测试辅助——见文末说明。

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
/// `Alphabet::UrlSafe` 与 `Alphabet::Standard` 只在 `+ / -`、`/ / _` 上不同。
pub fn Alphabet::is_url_safe(self : Alphabet) -> Bool {
  match self {
    Standard => false
    UrlSafe => true
  }
}

///|
/// 解码错误：**重命名**内核的 `DecodeError` 到本包。
///
/// 调用方 `match` 时**不写包限定**，变体名跨包可用：
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
/// 而 `pub type` 只搬得动类型名、搬不动变体限定名 `@lib.InvalidByte`。
/// **不写限定反而可用**——前提是本包对外暴露了该类型的具体值（`decode` 就返回它），
/// 类型推导会把变体一并解析（[S5 §3](docs/01-规格/S5-实施裁决与M1落地.md)）。
///
/// 注意一个反直觉的边界：**本包自己构造不出**这些变体（枚举对其它包只读，
/// 而本包只是别名的持有者）。受影响的是本包的测试：它们改在
/// `lib/internal/` 下的白盒用例里直接构造（那里是定义包）。故本层**不需要**
/// 「期望值构造器」——为测试服务的符号不进对外契约。
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
/// 变体在 `lib/internal` 构造——枚举对其它包是只读的
/// （`Cannot create values of the read-only type`），所以「三态各一个具名取值」
/// 不是审美选择，是唯一能跨包取得值的形态。
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
/// > **这是笔明账**：每次调用建 64 + 256 = 320 项表，约 360 ns，占外壳编码的
/// > 75.5%（0 B）/ 66.0%（3 B）/ 2.2%（1024 B）。换成顶层常量引擎的真实收益只有
/// > **3.9%（1024 B，噪声内）**，故**刻意不做**：为噪声级收益把「纯函数外壳」
/// > 改成模块级共享 `FixedArray`（引用语义，只读是约定而非类型保证）不划算——
/// > `Alphabet::url_safe()` 少一次 `copy()` 就会污染标准表，这类坑本仓踩过。
/// > 实测与裁决见 [S6 §1–§2](docs/01-规格/S6-性能实测与M3裁决.md)。
/// > 需要吞吐的调用方应改用 `encode_slice` / `decode_slice` 自持缓冲。
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
  alphabet~ : Alphabet = Standard,
  padding~ : Bool = true,
) -> String {
  let engine = engine(alphabet, padding, require_canonical_mode, false)
  let view = data[:]
  let out = FixedArray::make(@internal.encoded_len(view), b'\x00')
  // 内核只写有效符号，padding 由 `add_padding` 单点补——见 S4 §2.1。
  let written = @internal.encode_into(engine, view, out)
  let total = if padding {
    written + @internal.add_padding(written, engine.alphabet.padding, out)
  } else {
    written
  }
  // 容量按**字节**给：`StringBuilder` 内部是 `FixedArray[UInt16]`（每槽 2 字节），
  // 故 `size_hint = 2 * 符号数` 才恰好装满；传「符号数」只装一半，仍要增长一次。
  // 实测收益与口径见 S12 §3（跨产物 A/B 端到端编码 0.75–0.78×，输出逐字节不变）。
  let sb = StringBuilder(size_hint=2 * total)
  for i = 0; i < total; i = i + 1 {
    sb.write_char(out[i].to_int().unsafe_to_char())
  }
  sb.to_string()
}

///|
/// 把编码结果按 `padding` 换算成**目标总长度**：带 padding 是 `encoded_len`，
/// 不带是有效符号数 `n/3*4 + {0,2,3}[n%3]`。
///
/// 内核不写 padding，故「缓冲够不够」必须先按这个目标长度判——
/// 否则 `padding=true` 时会在 `add_padding` 里越界写。
fn encode_target_len(n : Int32, padding : Bool) -> Int32 {
  if padding {
    (n + 2) / 3 * 4
  } else {
    let rem = n % 3
    n / 3 * 4 + (if rem == 1 { 2 } else if rem == 2 { 3 } else { 0 })
  }
}

///|
/// 把字节视图编码写入调用方给定的定长缓冲，返回**写入的字节数**。
///
/// 这是**唯一**能避开输出二次拷贝的形态，对齐 crate 的 `encode_slice(&mut [u8]) -> usize`。
/// 缓冲不足返回 `Err(OutputSliceTooSmall)`——`encode` 内部即按目标长度分配，
/// 永远不会撞上这条。
pub fn encode_slice(
  data : BytesView,
  out : FixedArray[Byte],
  alphabet~ : Alphabet = Standard,
  padding~ : Bool = true,
) -> Result[Int32, EncodeSliceError] {
  let need = encode_target_len(data.length(), padding)
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
/// 便利形态（收 `String`）见 `decode_string`。
///
/// ```
/// @lib.decode(b"Zm9vYmFy"[:])             // Ok(b"foobar")
/// @lib.decode(b"Zg"[:])                   // Err(InvalidPadding) —— 默认 RequireCanonical
/// @lib.decode(b"Zg"[:], padding_mode=Indifferent)  // Ok(b"f")
/// ```
pub fn decode(
  input : BytesView,
  alphabet~ : Alphabet = Standard,
  padding_mode~ : DecodePaddingMode = require_canonical_mode,
  allow_trailing_bits~ : Bool = false,
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
    // 真要走到这一步，唯一的可能是长度估算与实际不符；用 `InvalidLength` 兜住，
    // 不静默返回「部分解码结果」。
    Err(OutputSliceTooSmall) =>
      Err(@internal.DecodeError::invalid_length(input.length()))
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
  alphabet~ : Alphabet = Standard,
  padding_mode~ : DecodePaddingMode = require_canonical_mode,
  allow_trailing_bits~ : Bool = false,
) -> Result[Int32, DecodeSliceError] {
  let engine = engine(alphabet, true, padding_mode, allow_trailing_bits)
  @internal.decode_into(engine, input, out)
}

///|
/// `decode` 的**便利形态**：收 `String`（先 `@utf8.encode` 成字节，再走 `decode`），**非主入口**。
///
/// 只对「本来就是 ASCII 的 base64 文本」等价（ASCII 下 UTF-8 编码是恒等变换）。
/// 含非 ASCII 字符的 `String` 会被编码成**别的字节**再解码——那类输入应走主入口 `decode`，
/// 自己决定字节来源（[S1 §5.3](docs/01-规格/S1-rust-base64-移植可行性分析.md)）。
pub fn decode_string(
  text : String,
  alphabet~ : Alphabet = Standard,
  padding_mode~ : DecodePaddingMode = require_canonical_mode,
  allow_trailing_bits~ : Bool = false,
) -> Result[Bytes, DecodeError] {
  decode(@utf8.encode(text)[:], alphabet~, padding_mode~, allow_trailing_bits~)
}

///|
/// 把解码错误渲染成一句可读的话，例：`InvalidByte(offset=4, byte=0x21)`。
///
/// 宿主想展示错误时走这里，不必自己 import internal 包
/// （internal 按可见性规则不可被外部 import）。需要**编程式**拿到 `offset`
/// 的场景见 [S5 §3](docs/01-规格/S5-实施裁决与M1落地.md) 的取舍说明。
pub fn describe(e : DecodeError) -> String {
  @internal.describe_decode_error(e)
}

///|
/// 把 `decode_slice` 的结果渲染成一句可读的话（宿主/调试用）。
pub fn describe_slice_result(r : Result[Int32, DecodeSliceError]) -> String {
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
