///|
/// 官方 core 的最小使用体 —— 与 `uselib` **同形态**（都只调一次 `encode`）。
///
/// 唯一差别是引入哪一家实现，故两者的增量之差就是「两家实现本身的体积之差」。
/// 这是**同平台对照**（都是 wasm-gc + 同一个运行时），最干净的一格。
fn main {
  println(@base64.encode(b"foob").length())
}
