///|
/// 编码表 / 解码表的构造（内核私有）。
///
/// 为什么要单列一个文件：这是 [S2 §3 P1](docs/01-规格/S2-现状基线与迁移缺口.md) 的落点——
/// 现在的 `encode_table()` / `decode_table()` **每次调用都 `FixedArray::make`**，
/// 而 rust-base64 用 `const fn` 在编译期展开。MoonBit 没有 `const fn` 等价物，
/// 只能「构造期生成 + 引擎对象缓存」，故这里产出的是**可缓存的值**。
///
/// > 骨架期：M3 落地后，本文件的函数只被 `engine.mbt` 调用一次（每引擎一次）。

///|
/// 构造「字节 → 6 位值」反查表（256 项）；非法字节值为 `-1`。
///
/// 该约定是 `decode` 判定 `InvalidByte` 的唯一依据
/// （白盒用例见 `lib/base64_wbtest.mbt` 的 `decode_table_marks_invalid_bytes`）。
///
/// TODO(M3)：从 `Alphabet.symbols` 派生；调用点收敛到 `Engine::new`。
/// TODO(M1)：padding 字符须在表中为 `-1` 或单列语义，勿与合法符号混同。
pub fn build_decode_table(_alphabet : Alphabet) -> FixedArray[Int] {
  abort("TODO(M3): build_decode_table —— 256 项，非法字节 = -1")
}

///|
/// 构造「6 位值 → 编码符号」表（64 项）。
///
/// TODO(M3)：即 `Alphabet.symbols` 本身或 `Bytes` 视图，避免多一次拷贝。
pub fn build_encode_table(_alphabet : Alphabet) -> FixedArray[Byte] {
  abort("TODO(M3): build_encode_table —— 64 项，索引即 6 位值")
}
