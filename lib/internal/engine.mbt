///|
/// 引擎对象：**表的持有者**（对齐 rust-base64 的 `GeneralPurpose`）。
///
/// 存在理由：MoonBit 没有 `const fn`，表只能**构造期生成**；若每次编解码现建，
/// 就是可测的损失（[S2 §3](docs/01-规格/S2-现状基线与迁移缺口.md)）。
///
/// > **这是笔明账，不是零成本**：`Engine::new` 要写 64 + 256 = 320 项。
/// > 外壳是纯函数形态，每次调用都会付这笔钱——实测约 360 ns，
/// > 占外壳编码 0 B / 3 B / 1024 B 的 **75.5% / 66.0% / 2.2%**。
/// > 但换成顶层常量引擎的真实收益只有 **3.9%（1024 B，噪声内）**，
/// > 故裁决为**维持每调用建一次**；取舍与复跑命令见
/// > [S6 §1–§2](docs/01-规格/S6-性能实测与M3裁决.md)。
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
