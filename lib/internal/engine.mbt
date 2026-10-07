///|
/// 引擎对象：**表的持有者**（对齐 rust-base64 的 `GeneralPurpose`）。
///
/// 存在理由（[S1 §3.3](docs/01-规格/S1-rust-base64-移植可行性分析.md)）：
/// MoonBit 没有 `const fn`，表只能**构造期生成**；若每次 `encode` / `decode` 现建，
/// 就是 [S2 §3 P1](docs/01-规格/S2-现状基线与迁移缺口.md) 的可测损失。
///
/// > **这是笔明账，不是零成本**：`Engine::new` 要写 64 + 256 = 320 项。
/// > 外壳是纯函数形态，每次调用都会付这笔钱（[S4 §2.3](docs/01-规格/S4-实施规格与落地顺序.md) 方案 A）。
/// > 之所以不引入全局缓存：它会给测试带来执行顺序依赖（AGENTS.md §三.2 铁律 7），
/// > 而收益尚无实测支撑。M3 后应补测「建表占比」再决定。
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
pub fn Engine::new(alphabet : Alphabet, config : Config) -> Engine {
  {
    alphabet,
    config,
    decode_table: build_decode_table(alphabet),
    encode_table: build_encode_table(alphabet),
  }
}

///|
/// 默认引擎：标准字母表 + 默认配置。
pub fn Engine::standard() -> Engine {
  Engine::new(Alphabet::standard(), Config::default())
}
