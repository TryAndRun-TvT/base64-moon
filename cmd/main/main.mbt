///|
/// 往返演示 + 不可解输入的错误展示。
///
/// 错误展示走 `@lib.describe`：包外**写不出** `Err(InvalidByte(..))` 这种期望值，
/// 因为 `lib/internal` 不允许被外部 import，变体名无从解析。
/// 想让错误变体名可用，得在**第三方包**里靠类型推导带进来——`cmd/main` 不是那样的位置
/// （[S5 §3](docs/01-规格/S5-实施裁决与M1落地.md)）。
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
