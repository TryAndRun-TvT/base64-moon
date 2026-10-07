///|
/// 内核错误类型：**4 类可定位错误**（对齐 rust-base64 0.23.1 的 `DecodeError`）。
///
/// 现状缺口见 [S2 §2.1 / §2.2](docs/01-规格/S2-现状基线与迁移缺口.md)：
/// 骨架期的 `decode` 返回 `Err(String)`——**人有得看、程序没法用**（拿不到 offset）。
///
/// 用 `suberror` 而非普通 `enum`：`Result[_, DecodeError]` 与 `raise` 两种调用风格
/// 都能挂同一个类型，且能 `derive` 做展示（`String` 只作展示，不作契约）。
///
/// **变体的字段值不是「大概齐」**：每个变体在什么条件下产生、offset 取哪个下标，
/// 逐条实测自 crate 0.23.1，汇总见
/// [S5 §2](docs/01-规格/S5-实施裁决与M1落地.md)。
///
/// > **枚举对其它包是只读的**（`Cannot create values of the read-only type`）：
/// > 变体的构造点只能在本包。外壳要报同一种错误，必须经本包提供的
/// > **具名构造器**（见文件末）——这不是审美选择，是 MoonBit 的包边界。
pub suberror DecodeError {
  /// 输入中混入了非字母表字节（padding 也算非法，除非它在合法位置）。
  /// `offset` = 0 基下标，`byte` = 原始字节。
  InvalidByte(Int, Byte)
  /// 有效符号总数 `% 4 == 1`（RFC 4648 §3.5：末尾不可能只剩 1 个有效符号）。
  ///
  /// 字段是**输入总长**，不是下标——实测 `"AAAAZ"` → `InvalidLength(5)`。
  InvalidLength(Int)
  /// 末尾符号的**低位冗余位非零**——符号在表里合法，但它编码的位被丢弃了。
  /// 例：`"Zh=="` → `InvalidLastSymbol(1, b'h')`。
  InvalidLastSymbol(Int, Byte)
  /// padding 数量 / 位置不符合所选 `DecodePaddingMode`，例：`"Zg"` 在 `RequireCanonical` 下。
  InvalidPadding
} derive(Debug, Eq)

///|
/// `decode_slice` 的返回错误：**解码失败**与**我给你的缓冲太小**是两件事。
///
/// 对齐 crate 的 `DecodeSliceError`（2 变体）。混进 `DecodeError` 会让调用方
/// 分不清「输入坏」和「我给小了」——前者该改数据，后者该放大缓冲。
///
/// 优先级（**实测**，见 [S5 §3](docs/01-规格/S5-实施裁决与M1落地.md)）：
/// 尾部 `rem == 1` 的便利检查 → 输出缓冲够不够 → 才轮到 padding 位置。
/// 所以 `decode_slice("=Zm9v", 1 字节缓冲)` 报 `OutputSliceTooSmall` 而不是 `InvalidByte`。
pub suberror DecodeSliceError {
  /// 输入本身解不出来。`offset` / `byte` 语义同 `DecodeError`。
  DecodeFailed(DecodeError)
  /// 输出缓冲不足。**不是**解码错误。
  OutputSliceTooSmall
} derive(Debug, Eq)

///|
/// `encode_slice` 的返回错误。crate 里它是独立类型且只有一个变体
/// （编码不会因为输入内容失败，只会因为缓冲不够）。
pub suberror EncodeSliceError {
  /// 输出缓冲不足。
  OutputSliceTooSmall
} derive(Debug, Eq)

///|
/// 把错误渲染成一句可读的话（展示用；**结构化字段才是契约**）。
pub fn describe_decode_error(e : DecodeError) -> String {
  match e {
    InvalidByte(offset, byte) =>
      "InvalidByte(offset=\{offset}, byte=\{to_hex(byte)})"
    InvalidLength(length) => "InvalidLength(\{length})"
    InvalidLastSymbol(offset, symbol) =>
      "InvalidLastSymbol(offset=\{offset}, symbol=\{to_hex(symbol)})"
    InvalidPadding => "InvalidPadding"
  }
}

///|
/// `0x21` 形态的十六进制展示。
fn to_hex(byte : Byte) -> String {
  let digits = "0123456789abcdef"
  let n = byte.to_int()
  let hi = digits[(n >> 4) & 0xF].to_int().unsafe_to_char()
  let lo = digits[n & 0xF].to_int().unsafe_to_char()
  "0x\{hi}\{lo}"
}

///|
/// 具名构造器：`InvalidByte`。
pub fn decode_error_invalid_byte(offset : Int, byte : Byte) -> DecodeError {
  InvalidByte(offset, byte)
}

///|
/// 具名构造器：`InvalidLength`。
pub fn decode_error_invalid_length(length : Int) -> DecodeError {
  InvalidLength(length)
}

///|
/// 具名构造器：`InvalidLastSymbol`。
pub fn decode_error_invalid_last_symbol(
  offset : Int,
  symbol : Byte,
) -> DecodeError {
  InvalidLastSymbol(offset, symbol)
}

///|
/// 具名构造器：`InvalidPadding`。
pub fn DecodeError::invalid_padding() -> DecodeError {
  InvalidPadding
}

///|
/// 具名构造器：输出缓冲不足（解码侧）。
pub fn DecodeSliceError::output_slice_too_small() -> DecodeSliceError {
  OutputSliceTooSmall
}

///|
/// 具名构造器：输出缓冲不足（编码侧）。
pub fn EncodeSliceError::output_slice_too_small() -> EncodeSliceError {
  OutputSliceTooSmall
}

///|
/// 把 `Debug` / `Eq` 的 impl 方法**显式登记**为 trait 方法，不让它们被隐式提升——
/// 它们是 `assert_eq` 所需的 trait impl，不是本类型的 API 面。
pub extend DecodeError with @debug.Debug::{to_repr}

///|
/// 见上。
pub extend DecodeError with Eq::{equal, not_equal}

///|
/// 见上。
pub extend DecodeSliceError with @debug.Debug::{to_repr}

///|
/// 见上。
pub extend DecodeSliceError with Eq::{equal, not_equal}

///|
/// 见上。
pub extend EncodeSliceError with @debug.Debug::{to_repr}

///|
/// 见上。
pub extend EncodeSliceError with Eq::{equal, not_equal}
