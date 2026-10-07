///|
/// 内核错误类型：**4 类可定位错误**（对齐 rust-base64 的 `DecodeError`）。
///
/// 现状缺口见 [S2 §2.1 / §2.2](docs/01-规格/S2-现状基线与迁移缺口.md)：
/// 当前 `decode` 返回 `Err(String)`——**人有得看、程序没法用**（拿不到 offset）。
/// 本类型是 [S2 §2.2] 建议的落地形态。
///
/// 用 `suberror` 而非普通 `enum` 的理由：`Result[_, DecodeError]` 与 `raise` 两种
/// 调用风格都能挂同一个类型，且能 `derive(Debug)` 做展示（`String` 只作展示，不作契约）。
///
/// > 骨架期：变体已定（M1 直接照此实现），**构造点待 M1**。
pub suberror DecodeError {
  /// 输入中混入了非字母表字节。`offset` = 0 基下标，`byte` = 原始字节。
  InvalidByte(Int, Byte)
  /// 有效符号总数 `% 4 == 1`（RFC 4648 §3.5：末尾不可能只剩 1 个有效符号）。
  InvalidLength(Int)
  /// 末尾符号的**低位冗余位非零**——非规范编码，例：`"Zh=="` 应为 `InvalidLastSymbol`。
  InvalidLastSymbol(Int, Byte)
  /// padding 数量 / 位置不符合所选 `DecodePaddingMode`，例：`"Zm9vYg==="`。
  InvalidPadding
}
