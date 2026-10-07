///|
/// 引擎对象：**表的持有者**（对齐 rust-base64 的 `GeneralPurpose`）。
///
/// 存在理由（[S1 §3.3](docs/01-规格/S1-rust-base64-移植可行性分析.md)）：
/// MoonBit 没有 `const fn`，表只能**构造期生成**；若每次 `encode` / `decode` 现建，
/// 就是 [S2 §3 P1](docs/01-规格/S2-现状基线与迁移缺口.md) 的可测损失。
/// 故引入引擎：**建一次，复用多次**——这与「纯函数 API」并不冲突，
/// 因为外壳会提供一个默认引擎（见 `lib/base64.mbt` 的 TODO）。
///
/// > 骨架期：结构已定，**构造与使用待 M3**。
pub struct Engine {
  alphabet : Alphabet
  config : Config
  /// 256 项反查表；`-1` = 非法字节。
  decode_table : FixedArray[Int]
  /// 64 项编码表；索引即 6 位值。
  encode_table : FixedArray[Byte]
}

///|
/// 构造引擎：一次性建好两张表。
///
/// TODO(M3)：调用 `build_decode_table` / `build_encode_table` 各一次，此后不再建表。
/// 完成判据（[S2 §4 M3](docs/01-规格/S2-现状基线与迁移缺口.md)）：
/// **对同一输入，M3 前后输出逐字节不变**（先有差分用例，再改实现）。
pub fn Engine::new(_alphabet : Alphabet, _config : Config) -> Engine {
  abort(
    "TODO(M3): Engine::new —— 建表一次，供后续所有调用复用",
  )
}

///|
/// 默认引擎（Standard 字母表 + 默认配置）。
///
/// TODO(M3)：外壳的纯函数形态 `encode(bytes)` 内部即用本引擎；
/// 注意**不要**用全局 `let` 可变状态（测试不得依赖执行顺序，AGENTS.md §三.2 铁律 7）。
pub fn Engine::standard() -> Engine {
  abort(
    "TODO(M3): Engine::standard —— 默认引擎，供纯函数外壳复用",
  )
}
