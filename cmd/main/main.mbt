///|
fn main {
  let text = "Hello, MoonBit!"
  let encoded = @lib.encode(@utf8.encode(text))
  println("input:   \{text}")
  println("base64:  \{encoded}")
  match @lib.decode(encoded) {
    Ok(bytes) => println("decoded: \{@utf8.decode_lossy(bytes)}")
    Err(e) => println("decode failed: \{e}")
  }
}
