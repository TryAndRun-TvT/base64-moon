///|
/// 编码表 / 解码表的构造（内核私有）。
///
/// 为什么要单列一个文件：这是 [S2 §3 P1](docs/01-规格/S2-现状基线与迁移缺口.md) 的落点——
/// 骨架期的 `encode_table()` / `decode_table()` **每次调用都 `FixedArray::make`**，
/// 而 crate 用 `const fn` 在编译期展开。MoonBit 没有 `const fn` 等价物，
/// 只能「构造期生成 + 引擎对象缓存」，故这里产出的是**可缓存的值**。

///|
/// 构造「字节 → 6 位值」反查表（256 项）；非法字节值为 `-1`。
///
/// 该约定是解码判定 `InvalidByte` 的唯一依据。**padding 字符也必须是 `-1`**：
/// 它由位置判据单独处理，若与合法符号混同，`"=Zm9v"` 这类输入会变成合法解码。
pub fn build_decode_table(alphabet : Alphabet) -> FixedArray[Int] {
  let table = FixedArray::make(256, -1)
  for i = 0; i < 64; i = i + 1 {
    table[alphabet.symbols[i].to_int()] = i
  }
  table
}

///|
/// 构造「6 位值 → 编码符号」表（64 项）。
///
/// 就是 `Alphabet.symbols` 本身，故直接返回其引用；**不做拷贝**
/// （表是只读的，每引擎一份，多拷一次没有收益）。
pub fn build_encode_table(alphabet : Alphabet) -> FixedArray[Byte] {
  alphabet.symbols
}
