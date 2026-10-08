///|
/// 内核配置：编码 / 解码的开关（对齐 rust-base64 的 `GeneralPurposeConfig`）。
///
/// 纪律：这些开关是**命名参数**（`padding?` / `padding_mode?`），不是新函数——
/// 一旦拆成 `encode_unpadded()` 之类，就是固化了 crate 已废弃的 8 个自由函数。
pub struct Config {
  /// 编码输出是否追加 `=` 填充。默认 `true`；URL-safe 场景惯例传 `false`。
  encode_padding : Bool
  /// 解码是否容忍末符号冗余位。默认 `false`（严格）。
  decode_allow_trailing_bits : Bool
  /// 解码时对 padding 的检查强度。
  padding_mode : DecodePaddingMode
}

///|
/// 解码对 `=` 填充的检查强度（对齐 crate 的 `DecodePaddingMode`）。
pub enum DecodePaddingMode {
  /// 有无 padding 都接受（缺 padding 容忍；多余 `=` 仍非法）。
  Indifferent
  /// 必须恰好是规范 padding：`(padding 数 + 有效符号数) % 4 == 0`。
  RequireCanonical
  /// 必须完全没有 padding。
  RequireNone
}

///|
/// 具名构造器：三个开关全显式。
///
/// 为什么不是 `Config { ... }` 记录字面量：MoonBit 的结构体对其它包是**只读**的，
/// 外壳（`lib/`）要按用户传的命名参数组合配置，只能走构造函数。
pub fn Config::new(
  encode_padding : Bool,
  decode_allow_trailing_bits : Bool,
  padding_mode : DecodePaddingMode,
) -> Config {
  { encode_padding, decode_allow_trailing_bits, padding_mode, }
}

///|
/// 默认配置：`padding = true` / `trailing_bits = false` / `RequireCanonical`。
///
/// > `RequireCanonical` 是**实测值，不是选出来的**：crate `GeneralPurposeConfig::new()`
/// > 实测即此（[S5 §2.1](docs/01-规格/S5-实施裁决与M1落地.md)）。
pub fn Config::default() -> Config {
  Config::new(true, false, RequireCanonical)
}

///|
/// 具名构造器：有无 padding 都接受。
pub fn DecodePaddingMode::indifferent() -> DecodePaddingMode {
  Indifferent
}

///|
/// 具名构造器：必须恰好是规范 padding。
pub fn DecodePaddingMode::require_canonical() -> DecodePaddingMode {
  RequireCanonical
}

///|
/// 具名构造器：必须完全没有 padding。
pub fn DecodePaddingMode::require_none() -> DecodePaddingMode {
  RequireNone
}
