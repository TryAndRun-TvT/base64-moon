// lib/ —— **公共 API 外壳**（facade）。
//
// 本包（lib/facade.mbt）是唯一对使用者可见的层：它把内核（lib/internal/）的
// 零分配接口**物化**成好用的 `String` / `Bytes` 形态，并持有「默认引擎」。
//
// 分层纪律（见 AGENTS.md §二.1 与
// docs/01-规格/S1-rust-base64-移植可行性分析.md §9）：
//   · 符号表 / padding / 错误语义一律在 lib/internal/ 落地，本层**不重复实现**；
//   · 本层可以 import lib/internal/*，internal **不得**反向 import 本层；
//   · `decode` 的入参最终要落在**字节视图**上（非 `String`），理由见 S1 §5.3。
//
// 现状：骨架期——本文件是「能过 RFC 4648 §10 官方向量」的最小实现（M0 前基线），
// 按 docs/01-规格/S2-现状基线与迁移缺口.md §4 的路线图 M0→M5 逐步替换为内核调用。

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
/// 把字节数组编码为 Base64 字符串。
///
/// > **目标签名（M2 落定）**：`encode(data, alphabet?, padding? : Bool = true) -> String`。
/// > `padding=false` 是 URL-safe 场景的惯例形态，现状**无法产出无 padding 输出**
/// > （缺口见 [S2 §2.3](docs/01-规格/S2-现状基线与迁移缺口.md)）。
///
/// TODO(M2)：把 `padding?` 透传给内核 `Config.encode_padding`。
/// TODO(M3)：改为「默认引擎 + 内核 `encode_into` 写入 `FixedArray[Byte]`，末尾逐 `Char` 物化」——
///   注意物化**不是**提速点（[S1 §6.1]），换实现只为消除每次调用现建表；输出须逐字节不变。
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
///
/// > **目标签名（M0 落定）**：入参改**字节视图**、返回改 `Result[Bytes, DecodeError]`，
/// > 并另出定长形态 `decode_slice(input, out) -> Result[Int, DecodeError]`。
/// > 理由见 [S2 §2.4](docs/01-规格/S2-现状基线与迁移缺口.md)：
/// > `String` 是 UTF-16，用它当字节源是**前提错**；`Err(String)` 是**程序没法用**。
/// > 本函数保留为**便利重载**（转调内核），不是主入口。
///
/// TODO(M0)：落定签名后，本函数体改为 `decode(input_bytes)` 的薄转调。
/// TODO(M1)：四条判据移入内核 `decode_into` / `decode_suffix`——本层**不再**做输入校验。
/// TODO(M2)：透传 `padding_mode?` 与 `allow_trailing_bits?`。
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
