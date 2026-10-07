///|
/// 字母表：64 个编码符号 + 一个填充字符（对齐 rust-base64 的 `alphabet::Alphabet`）。
///
/// 与对外 `lib/Alphabet` 的区别：那个是**变体开关**（只认 `Standard` / `UrlSafe`），
/// 这个是内核的**数据结构**，允许自定义符号集与填充字符
/// （rust-base64 预置六张：Standard / UrlSafe / Crypt / Bcrypt / IMAP-MUTF7 / BinHex）。
///
/// > 骨架期：仅声明形态与不变量，**实现待 M3**。
/// > 不变量：`symbols` 恒为 64 字节；`padding` 不出现在 `symbols` 里（否则反查表自相矛盾）。
pub struct Alphabet {
  /// 64 个编码符号，下标即 6 位值。
  symbols : FixedArray[Byte]
  /// 填充字符，默认 `b'='`（Crypt 用 `.`，故必须可配）。
  padding : Byte
}

///|
/// 构造标准字母表（`+` / `/`，padding `=`）。
///
/// TODO(M3)：从 `b"ABC…+/"` 构造，是 `pub fn Alphabet::standard()` 的内核形式。
pub fn Alphabet::standard() -> Alphabet {
  abort("TODO(M3): 内核 standard() —— 64 符号 + padding `=`")
}

///|
/// 构造 URL-safe 字母表（`-` / `_`，padding `=`）。
///
/// TODO(M3)：与 `standard()` 只差两个符号，实现时勿复制整串字面量（用替换或常量表）。
pub fn Alphabet::url_safe() -> Alphabet {
  abort("TODO(M3): 内核 url_safe() —— 仅 `+`→`-`、`/`→`_`")
}
