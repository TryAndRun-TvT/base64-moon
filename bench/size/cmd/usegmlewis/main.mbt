///|
/// 第三方 gmlewis/base64 的最小使用体 —— 与 `uselib` / `usecore` **同形态**
/// （都只调一次编码）。唯一差别是引入哪一家，故增量之差即「实现本身的体积之差」。
///
/// gmlewis 的编码入口收 `FixedArray[Byte]`（非 `Bytes`），故 `to_fixedarray()`
/// 是**其 API 形态的一部分**、不算额外包装；两端都只调用一次编码。
fn main {
  println(@gmlewis.std_encode2str(b"foob".to_fixedarray()).length())
}
