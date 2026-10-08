///|
/// 内核错误类型：**4 类可定位错误**（对齐 rust-base64 0.23.1 的 `DecodeError`）。
///
/// 用 `suberror` 而非 `enum`：`Result[_, DecodeError]` 与 `raise` 两种调用风格
/// 都能挂同一个类型，且能 `derive` 做展示（`String` 只作展示，不作契约）。
///
/// **字段值是实测的，不是推断的**：每个变体在什么条件下产生、`offset` 取哪个下标，
/// 逐条实测自 crate 0.23.1（[S5 §2](docs/01-规格/S5-实施裁决与M1落地.md)）。
///
/// **变体只能在本包构造**——枚举对其它包是只读的
/// （`Cannot create values of the read-only type`），故包外不需要「具名构造器」：
/// 定义包写 `InvalidByte(4, b'!')` 即可，别的包既构造不出也没必要构造。
/// 外壳 `lib/` 只做类型重命名与错误透传，它自己的测试按形状断言（见 `lib/facade.mbt`）。
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
/// 对齐 crate 的 `DecodeSliceError`。混进 `DecodeError` 会让调用方分不清
/// 「输入坏」（该改数据）和「我给小了」（该放大缓冲）。
///
/// 优先级**实测自 crate**：尾部 `rem == 1` 的便利检查 → 缓冲够不够 → 才轮到
/// 「padding 出现在位置 0/1」。故 `decode_slice("=Zm9v", 1 字节缓冲)` 报
/// `OutputSliceTooSmall` 而不是 `InvalidByte`
/// （[S5 §3](docs/01-规格/S5-实施裁决与M1落地.md)）。
pub suberror DecodeSliceError {
  /// 输入本身解不出来。字段语义同 `DecodeError`。
  DecodeFailed(DecodeError)
  /// 输出缓冲不足。**不是**解码错误。
  OutputSliceTooSmall
} derive(Debug, Eq)

///|
/// `encode_slice` 的返回错误。编码不会因为输入内容失败，只会因为缓冲不够，
/// 故只有一个变体（对齐 crate 的同名类型）。
pub suberror EncodeSliceError {
  /// 输出缓冲不足。
  OutputSliceTooSmall
} derive(Debug, Eq)

///|
/// 把错误渲染成一句可读的话（**展示用**；结构化字段才是契约）。
///
/// 存在的理由：宿主想打印错误时不必自己 import `internal` 包
/// （它按可见性规则不可被外部 import）。
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

///|
/// 取 `EncodeSliceError::OutputSliceTooSmall`。
///
/// 外壳（`encode_slice`）也要报这个错误，而枚举对**其它包**只读——
/// 本包是定义包，故由本包提供取值入口。这不是「为测试服务的构造器」：
/// `encode_slice` 的缓冲不足是真实用户会撞到的路径。
pub fn EncodeSliceError::output_slice_too_small() -> EncodeSliceError {
  OutputSliceTooSmall
}

///|
/// 取 `DecodeError::InvalidLength`。
///
/// 外壳的 `decode` 在「长度估算兜底」这条不可达路径上报它（见 `facade.mbt`），
/// 而枚举对其它包只读，故由本包提供取值入口。
pub fn DecodeError::invalid_length(length : Int) -> DecodeError {
  InvalidLength(length)
}
