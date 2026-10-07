///|
/// 往返演示 + 不可解输入的错误展示。
///
/// 错误展示为何不直接 `match` 变体名：那要求 import `lib/internal`，
/// 而 internal 包按可见性规则不可被外部 import。可用的形态是 `@lib` 提供的
/// 结构化访问器（见 S5 §4）。这里演示「拿到 offset 与出错字节」这一件事。
fn main {
  let text = "Hello, MoonBit!"
  let encoded = @lib.encode(@utf8.encode(text))
  println("input:   \{text}")
  println("base64:  \{encoded}")
  match @lib.decode(@utf8.encode(encoded)[:]) {
    Ok(bytes) => println("decoded: \{@utf8.decode_lossy(bytes)}")
    Err(_) => println("decode failed")
  }
  // 错误可定位：报出 offset 与出错字节，而不是只给一句「失败了」。
  let bad = b"Zm9v!"
  match @lib.decode(bad[:]) {
    Ok(_) => println("unexpected ok")
    Err(e) => println("bad input: \{@lib.describe(e)}")
  }
}
