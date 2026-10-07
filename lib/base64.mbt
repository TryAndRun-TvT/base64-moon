///|
/// Base64 字母表变体（RFC 4648）；由 `standard()` / `url_safe()` 取用。
pub enum Alphabet {
  /// 标准字母表（`+` / `/`）
  Standard
  /// URL 安全字母表（`-` / `_`）
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
/// 取字母表对应的 64 个编码字符。
fn encode_table(alphabet : Alphabet) -> FixedArray[Byte] {
  match alphabet {
    Standard =>
      b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".to_fixedarray()
    UrlSafe =>
      b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".to_fixedarray()
  }
}

///|
/// 把字节数组编码为 Base64 字符串（带 `=` 填充）。
pub fn encode(data : Bytes, alphabet? : Alphabet = Standard) -> String {
  let table = encode_table(alphabet)
  let out = StringBuilder()
  let mut i = 0
  let n = data.length()
  while i + 2 < n {
    let (b0, b1, b2) = (
      data[i].to_int(),
      data[i + 1].to_int(),
      data[i + 2].to_int(),
    )
    out.write_char(table[b0 >> 2].to_int().unsafe_to_char())
    out.write_char(
      table[((b0 & 0x03) << 4) | (b1 >> 4)].to_int().unsafe_to_char(),
    )
    out.write_char(
      table[((b1 & 0x0F) << 2) | (b2 >> 6)].to_int().unsafe_to_char(),
    )
    out.write_char(table[b2 & 0x3F].to_int().unsafe_to_char())
    i += 3
  }
  match n - i {
    1 => {
      let b0 = data[i].to_int()
      out.write_char(table[b0 >> 2].to_int().unsafe_to_char())
      out.write_char(table[(b0 & 0x03) << 4].to_int().unsafe_to_char())
      out.write_string("==")
    }
    2 => {
      let (b0, b1) = (data[i].to_int(), data[i + 1].to_int())
      out.write_char(table[b0 >> 2].to_int().unsafe_to_char())
      out.write_char(
        table[((b0 & 0x03) << 4) | (b1 >> 4)].to_int().unsafe_to_char(),
      )
      out.write_char(table[(b1 & 0x0F) << 2].to_int().unsafe_to_char())
      out.write_char('=')
    }
    _ => ()
  }
  out.to_string()
}

///|
/// 把字母表映射为「字节 → 6 位值」的反查表；非法字节值为 -1。
fn decode_table(alphabet : Alphabet) -> FixedArray[Int] {
  let table = FixedArray::make(256, -1)
  let chars = encode_table(alphabet)
  for i = 0; i < 64; i = i + 1 {
    table[chars[i].to_int()] = i
  }
  table
}

///|
/// 解码 Base64 字符串（容忍缺失的 `=` 填充；遇非法字符返回 `Err`）。
pub fn decode(
  text : String,
  alphabet? : Alphabet = Standard,
) -> Result[Bytes, String] {
  let table = decode_table(alphabet)
  let buf = Buffer::Buffer()
  let acc = Ref(0)
  let bits = Ref(0)
  for ch in text {
    let code = ch.to_int()
    if code == '='.to_int() {
      break
    }
    let v = if code >= 0 && code < 256 { table[code] } else { -1 }
    if v < 0 {
      return Err("invalid base64 character: \{ch}")
    }
    acc.val = (acc.val << 6) | v
    bits.val += 6
    if bits.val >= 8 {
      bits.val -= 8
      buf.write_byte(((acc.val >> bits.val) & 0xFF).to_byte())
    }
  }
  Ok(buf.to_bytes())
}

///|
/// `Alphabet::UrlSafe` 与 `Alphabet::Standard` 只在 `+ / -`、`/ / _` 上不同。
pub fn Alphabet::is_url_safe(self : Alphabet) -> Bool {
  match self {
    Standard => false
    UrlSafe => true
  }
}
