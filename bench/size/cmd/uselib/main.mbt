///|
/// 最小使用体：**只调一次** `@lib.encode`，量「引入本库」的体积增量。
///
/// 输入是常量，但结果必须被**读**（`println`），否则整段可被 DCE
/// ——那量到的是「空 exec」，不是「引入本库」（bench/README.md 口径 ④）。
fn main {
  println(@lib.encode(b"foob").length())
}
