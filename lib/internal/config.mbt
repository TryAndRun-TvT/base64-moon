///|
/// 内核配置：编码 / 解码的开关（对齐 rust-base64 的 `GeneralPurposeConfig`）。
///
/// 对齐表见 [S1 §3.2](docs/01-规格/S1-rust-base64-移植可行性分析.md)；
/// 现状缺口见 [S2 §2.3](docs/01-规格/S2-现状基线与迁移缺口.md)：
/// 当前 `encode` **恒带 `=`**、`decode` **恒容忍冗余位**、**无 padding 检查强度**。
///
/// > 骨架期：形态已定，**实现待 M2**。
/// > 纪律：这些开关是**命名参数**（`padding?` / `padding_mode?`），不是新函数——
/// > 一旦拆成 `encode_unpadded()` 之类，就是固化了 rust-base64 已废弃的 8 个自由函数（S1 §9.3）。
pub struct Config {
  /// 编码输出是否追加 `=` 填充。默认 `true`；URL-safe 场景惯例传 `false`。
  encode_padding : Bool
  /// 解码是否容忍末符号冗余位。默认 `false`（严格）。
  decode_allow_trailing_bits : Bool
  /// 解码时对 padding 的检查强度。默认 `Indifferent`。
  padding_mode : DecodePaddingMode
}

///|
/// 解码对 `=` 填充的检查强度（对齐 rust-base64 的 `DecodePaddingMode`）。
pub enum DecodePaddingMode {
  /// 有无 padding 都接受（缺 padding 容忍；多余 `=` 仍非法）。
  Indifferent
  /// 必须恰好是规范 padding（长度与位置都合规）。
  RequireCanonical
  /// 必须完全没有 padding。
  RequireNone
}

///|
/// 默认配置：`padding = true` / `trailing_bits = false` / `Indifferent`。
///
/// TODO(M2)：作为 `encode` / `decode` 命名参数的默认值；**不要**做成全局可变状态。
pub fn Config::default() -> Config {
  abort(
    "TODO(M2): Config::default —— padding=true / trailing_bits=false / Indifferent",
  )
}
