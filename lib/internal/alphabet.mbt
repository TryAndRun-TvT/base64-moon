///|
/// 字母表：64 个编码符号 + 一个填充字符（对齐 rust-base64 的 `alphabet::Alphabet`）。
///
/// 与对外 `lib/Alphabet` 的区别：那个是**变体开关**（只认 `Standard` / `UrlSafe`），
/// 这个是内核的**数据结构**，允许自定义符号集与填充字符
/// （crate 预置六张：Standard / UrlSafe / Crypt / Bcrypt / IMAP-MUTF7 / BinHex）。
///
/// 不变量：`symbols` 恒为 64 字节；`padding` 不出现在 `symbols` 里。
pub struct Alphabet {
  /// 64 个编码符号，下标即 6 位值。
  symbols : FixedArray[Byte]
  /// 填充字符，默认 `b'='`（Crypt 用 `.`，故必须可配）。
  padding : Byte
}

///|
/// 标准字母表（`+` / `/`，padding `=`）。
pub fn Alphabet::standard() -> Alphabet {
  {
    symbols: b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".to_fixedarray(),
    padding: b'=',
  }
}

///|
/// URL-safe 字母表（`-` / `_`，padding `=`）。
///
/// 与 `standard()` 只差**两个位置**（62 / 63），不是两个「ASCII 码」：
/// 表的下标是 6 位值，不是字符的码点。写成 `symbols[b'+'.to_int()]` 会把
/// 43 号位置（`r` 的槽）改成 `-`——这错曾被 `encode_urlsafe_uses_alt_chars` 抓到。
/// （`q` 是 42 号槽；43 是 `r`。这处注释先前写错了，白盒用例 `url_safe_is_an_independent_copy` 抓到。）
///
/// 复制这一步同样不能省：`FixedArray` 是引用语义，原地改会连带改掉标准表，
/// 于是 `encode(x)` 与 `encode(x, alphabet=url_safe())` 输出相同。
pub fn Alphabet::url_safe() -> Alphabet {
  let symbols = Alphabet::standard().symbols.copy()
  symbols[62] = b'-'
  symbols[63] = b'_'
  { symbols, padding: b'=', }
}
