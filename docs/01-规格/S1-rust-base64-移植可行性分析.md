# S1 · rust-base64 移植至 MoonBit 的可行性分析

> **状态**：现行　｜　日期：2026-10-07　｜　索引：[docs/README.md](../README.md) §1

> 一句话结论：**移植可行，目标应是「非流式 API 兼容」；难点不在算法，在签名形态**。
> crate 的 `no_std` 分层（`core` / `alloc` / `std`）正好给出本项目的架构模板：
> **零分配内核 + 物化外壳**，本文据此重排复杂度。
> 本机实测澄清了三件容易误判的事：`wasm-gc` **不会自动向量化**（显式 `@v128` 才出指令）；
> `String` 是 UTF-16 且 **`Bytes → String` 是重解释不是解码**；
> **物化路径不是提速点**（解码侧的真提速点是「4 字符 → 3 字节」展开，1.6–2.0×）。
> 详见 [§3.5](#35-向量层b-层机制不可搬目标可搬)、[§5.3](#53-string-是-utf-16字节与字符之间没有免费的桥) 与
> [§6.1](#61-一处必须更正的量物化路径不是提速点)。

## 0. 本文的范围与证据口径

- **被研究对象**：`marshallpierce/rust-base64`，本地克隆于 `5b98ee1`（2026-08-18），版本 `0.23.1`。
- **对照对象**：`moonbitlang/core` 的 `encoding/base64`（本地克隆于 `90558a3`，2026-10-07），
  以及本仓库骨架 `lib/base64.mbt`。
- **本机实测**：MoonBit `0.1.20260920 (914d7da)`、`moonc` 同版本；`wasm-gc` / `wasm` / `native` 三后端。
- **口径纪律**：本文每个数字都附**复跑方式或出处**；无法复跑的口径一律标注「引自官方源码」。
  性能口径统一为「**输入字节 / 秒**」（等长循环取总时长，`wasm-gc` / `release`）。
  [ISSUE #3 实测评论](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/issues/3) 是历史的另一套口径，
  两处不可直接比较；本文 §6.1 的数字以本节口径为准。

## 1. 结论速览

| 被移植物 | 体量 | MoonBit 可行性 | 建议 |
|---------|------|:--------------:|------|
| 标量编解码内核（`general_purpose` + 后缀校验） | ≈ 600 行 | ✅ 直接可搬 | **做**：本仓库的主战场 |
| 配置与错误语义（3 配置项 / 4 错误变体 / 3 padding 模式） | ≈ 200 行 | ✅ 可直接搬 | **做**：这是与官方实现拉开差距的关键 |
| 字母表体系（`Symbol` / `Alphabet` / 6 张预置表 / 自定义 padding） | 404 行 | ⚠️ 可搬，需重设计 | **做**：把「表」从 `const` 变成构造期生成 |
| 定长输出 API 形态（`encode_slice` / `decode_slice`） | `encode.rs` + `decode.rs` 共 929 行 | ✅ 可搬（**是签名关键，非性能关键**） | **做**：`FixedArray[Byte]` 可对齐 Rust `&mut [u8]`；性能瓶颈另在批量内核 |
| `std::io` 流式层（`read` / `write` / `display`） | 1219 行 | ❌ 无对应物 | **不做**：MoonBit 无 `io::Read`/`io::Write` trait |
| `chunked_encoder` 分块节律（F 层内未门控部分） | 含在上行 | ⚠️ 可搬（**无 `std` 依赖**，见 §3.4） | **可做**：搬「节律」不搬 trait 外壳 |
| AVX2 / NEON 向量层 | 807 行 | ❌ 无对应物 | **不做**：取而代之，用 `V128` 写 SIMD128（且**不进首版**） |
| `Engine` trait + `Simd` 运行时分发 | 516 + 807 行（已计入上两行） | ⚠️ 形态可借鉴，机制不适用 | **部分借鉴**：trait object 可用，但运行时分发在 wasm-gc 无意义 |
| 测试矩阵（`engine/tests.rs` 2182 行 + 三处 `*_tests.rs`，rstest 参数化全引擎遍历） | 3364 行 | ⚠️ 需换形态 | **借鉴判据，不搬框架**：MoonBit 无 rstest，用「差分 + 长度全扫」替代 |

**一句话**：crate 的 9600 行 Rust 里，**可搬运约 31%**（A/C/D/E 层的实现，≈ 2950 行中约 70% 可直接落），
**必须重设计约 19%**（`Engine` 抽象、表缓存、SIMD128 重写），**不要搬约 46%**（F 流式层的 trait 外壳 + B 层 x86/ARM 内建函数），
**必须换形态约 35%**——但最后这块（`G`/`H` 测试与基准）**恰恰是最该学、最不该省的部分**。
复杂度**不在算法**——算法是中学生的位运算；复杂度在**语义完整性**（4 判据）与**签名形态**（`String` 是 UTF-16，见 [§5.3](#53-string-是-utf-16字节与字符之间没有免费的桥)）。

> 口径说明：上表「体量」列是可操作的分层实测值（复跑见 [§7](#7-复跑方式)），
> 与本段的百分比为**估值**（同一文件可能横跨多类，无法精确切分），仅用于排序优先级，勿引用为精确数字。

## 2. 移植对象全景：crate 的 9600 行怎么分的

`find . -name '*.rs' | xargs wc -l` 的实测分布（本地克隆 `5b98ee1`，`*.rs` 合计 9600 行）：

| 层 | 文件 | 行数 | 角色 |
|----|------|-----:|------|
| **A 标量内核** | `engine/general_purpose/{mod,decode,decode_suffix}.rs` | 1089 | 查表编解码 + 后缀校验 + 边界检查 |
| **B 向量内核** | `engine/simd.rs` | 807 | AVX2 / NEON / 运行时分发 |
| **C 配置与元数据** | `engine/mod.rs`（trait + 配置 + `DecodeMetadata`） | 516 | `Engine` trait、`Config`、`DecodePaddingMode` |
| **D 字母表** | `alphabet.rs` | 404 | `Symbol`、`Alphabet`、6 张预置表 |
| **E API 门面** | `encode.rs` + `decode.rs` | 929 | `encode_slice`/`decode_slice`/错误类型/长度计算 |
| **F 流式层** | `read/decoder.rs` + `write/{encoder,encoder_string_writer}.rs` + `chunked_encoder.rs` + `display.rs` | 1219 | `io::Read`/`io::Write` 适配 |
| **G 测试** | `engine/tests.rs` + `read/decoder_tests.rs` + `write/encoder_tests.rs` + `src/tests.rs` | 3364 | 语义矩阵 |
| **H 外部测试/基准/fuzz** | `tests/` + `benches/` + `fuzz/` | ≈ 600 | 对拍与性能 |

> 复跑：`cd <clone> && find . -name '*.rs' | xargs wc -l | sort -n`。

**关键观察**：`G + H` 占 **41%**——这个 crate 的重量不在实现，在**语义矩阵**。
移植时若只搬实现不搬判据，等于把 0.23 的历次修正（`RELEASE-NOTES.md` 记录了 padding、trailing bits、
`InvalidLastSymbol` 等多轮修错）**重踩一遍**。这是本仓库最应该学习的地方。

## 3. 逐层对照：能搬什么，要改什么

### 3.1 标量内核（A 层）——直接可搬，约 300 行有效逻辑

`encode_scalar_tail` 的核心是一个 4 块展开的循环：**每次读 6 字节、写 8 个字符**，
用一次 `u64` 读取换 4 次边界检查。这依赖 Rust 的「切片越界检查可被证明消除」。
MoonBit 侧等价物是 `FixedArray.unsafe_get` / 循环不变量，**语义可 1:1 对齐**，但需要自己保证不越界。

解码侧 `decode_complete_quads` 同理：一次消费 4 个字符出 3 字节。真正的复杂度在 `decode_suffix`（170 行），
它要一次性回答四个问题：

1. 末尾 2~4 个符号是否合法？
2. padding 的数量与位置是否符合所选 `DecodePaddingMode`？
3. 最后一个符号的**低位冗余位**是否为零（`decode_allow_trailing_bits`）？
4. 输入里是否混入了 `=`（非末尾 padding 一律非法）？

这四个判据是 RFC 4648 §3.5 的可执行化，**与语言无关**，建议原样搬成 MoonBit 的 `Result` 分支。

> **本仓库现状**：`lib/base64.mbt` 的 `decode` 只有「遇 `=` 即停 + 非法字符报错」，
> 上述 4 条判据**一条都没有**。这是与 crate 差距最大的地方，也是「可用性」的真实门槛。

### 3.2 配置与错误语义（C 层）——建议全搬

| Rust 侧 | 语义 | MoonBit 建议形态 |
|---------|------|-----------------|
| `GeneralPurposeConfig { encode_padding }` | 输出是否带 `=` | 命名参数（已有 `alphabet?`，加 `padding?`） |
| `decode_allow_trailing_bits` | 容忍末符号冗余位 | 命名参数，默认 `false` |
| `DecodePaddingMode::{Indifferent, RequireCanonical, RequireNone}` | padding 检查强度 | `pub enum`（已有 `Alphabet` 先例） |
| `DecodeError::{InvalidByte, InvalidLength, InvalidLastSymbol, InvalidPadding}` | 4 类可定位错误 | `pub suberror`，携带 offset/byte |
| `DecodeMetadata { decoded_len, padding_offset }` | 解码结果元数据 | 返回值元组或 `struct` |

**这是「官方实现普遍不如第三方」命题的正面教材**：crate 的错不是「不严谨」，而是**太严谨**——
它的默认配置把可定位错误、非规范 padding、冗余位全查了一遍。
本仓库的正确策略不是「抄性能」，而是**先把这套语义补齐**，再在热路径上想办法不掉速。

### 3.3 字母表（D 层）——可搬，但需重设计

crate 用 `const fn` 在**编译期**把字母表展开成 64 字节编码表 + 256 字节解码表，并预置了
`STANDARD` / `URL_SAFE` / `CRYPT` / `BCRYPT` / `IMAP_MUTF7` / `BIN_HEX` 六张表，还支持**自定义 padding 字符**。

MoonBit 的对应手段是**构造期生成表**（`fn build_tables(alphabet) -> (FixedArray[Byte], FixedArray[Int])`），
代价是每次调用都要建表——所以**必须配套「引擎对象」概念**（把表缓存起来复用一个值），
这正是 crate 里 `GeneralPurpose` 结构体的存在理由，**建议照搬这个结构，而不是每次函数调用现建表**。

> **本仓库现状**：`encode_table()` / `decode_table()` 每次调用都新建 64/256 字节数组。
> 这是当前实现可测的性能损失之一，也是性能篇要解决的问题。

### 3.4 流式层（F 层）——不可移植

`read/decoder.rs`（`io::Read` 适配）、`write/{encoder,encoder_string_writer}.rs`（`io::Write` 适配）、
`chunked_encoder.rs`、`display.rs`（`Display` trait）四者合计 1219 行。

**先更正一条上一版的粗判**：这一层**不是铁板一块**。实测 `src/lib.rs` 的门控：

```rust
mod chunked_encoder;                 // 未加 #[cfg] —— no_std 下仍编译
pub mod display;                     // 未加 #[cfg]，但 Display 只在 std 有意义
#[cfg(any(feature = "std", test))]
pub mod read;
#[cfg(any(feature = "std", test))]
pub mod write;
```

即 `chunked_encoder` 的**分块节律**（1024 字节块 + 尾块）**不依赖 `std`**，它是
`DecoderReader` 与 `ChunkedEncoder` 共用的内部机制，属于**可搬的「骨」**；
搬不动的只是 `io::Read` / `io::Write` / `Display` 这三个 **trait 外壳**。

结论：**trait 外壳不做**（MoonBit 无对应抽象，硬造等于自建生态）；
**分块节律可搬**，但按 [S2 §4](S2-现状基线与迁移缺口.md#4-迁移路线图可勾选) 的评级**优先级低**
（它是常量循环，且真正复用它的 `DecoderReader` 搬不了）。宿主需要流式场景时，
正确做法是在宿主侧按同样的「整块 + 尾块」节奏调用本库的 slice API。

### 3.5 向量层（B 层）——机制不可搬，目标可搬

crate 的 `simd.rs` 用 `#[target_feature(enable = "avx2")]` + `_mm256_*` 内建函数，
再加 `std::is_x86_feature_detected!` 做运行时分发。MoonBit 侧**三点都不对应**：

- 无 `#[target_feature]`：后端在编译期固定，没有「同一份代码编译出两条路径」的机制；
- 无 x86/ARM 内建函数：MoonBit 的载体是 SIMD128（`V128`），**128 位一条**，而非 256 位一条；
- 无运行时分发必要：`wasm-gc` 的目标是单一代（Wasm GC 提案），SIMD128 在同代里可**显式**调用。

**必须先破一个常见误解**：`wasm-gc` **不是**「会自动向量化」的后端。实测（复跑见 §7）：

| 代码 | 产物 `0xFD`（SIMD 前缀）指令数 |
|------|:---:|
| 纯标量（求 + 查表循环） | **0** |
| 显式 `i8x16_swizzle` + `v128_and_` + `v128_xor` | **9** |

即：**通用标量代码不会被自动向量化；只有显式调用 `@v128` API 才会出真指令**。
因此 SIMD 路径是**从零手写**，不是「把标量代码交给编译器」。

另有两个 API 形态上的坑，直接影响写法：

- 位运算函数名带尾下划线：是 `v128_and_`，不是 `v128_and`；
- 这批函数标了 `#internal(experimental)`，调用会触发 `alert_experimental` 告警，
  需在包的 `warnings` 中显式处理（与根包关 `-29` 同法）。

结论：**不是「搬 AVX2 代码」，而是「用 SIMD128 重写同样三件事」**——
① 6 位值 ↔ ASCII 的位运算映射；② 无效字符的向量化检出；③ 装载与分块。
且按用户既定约束，**本项不列入首版**（`wasm-gc` 单目标下收益需先有可信标量基线才谈得上）。

## 4. 关键机制对照表

| 机制 | Rust crate | MoonBit / wasm-gc | 移植动作 |
|------|-----------|-------------------|---------|
| 输入缓冲 | `&[u8]` / `&mut [u8]` 切片 | `Bytes` / `BytesView` / `FixedArray[Byte]` | 用 `BytesView` 做零拷贝入参 |
| 输出缓冲 | `&mut [u8]` 就地写 | `Buffer`（字节）/ `FixedArray`（定长） | 用 `FixedArray` 定长输出 + 末尾整体转 `String` |
| 表 | `const fn` 编译期展开 | 构造期 `FixedArray` | 引入「引擎对象」缓存表 |
| 错误 | `enum DecodeError` + `?` | `pub suberror` + `raise`/`Result` | 语义 1:1，形态本地化 |
| 整数运算 | `u64` + `from_be_bytes` | `UInt64` + 手动组装 | 语义相同，改写表达式即可 |
| 向量 | `_mm256_*` / `vld1q_*` | `@moonbitlang/core/v128` → `V128` | **重写**，非翻译 |
| 运行时分发 | `is_x86_feature_detected!` | 无（编译期决定） | **删除该设计** |
| 惰性输出 | `Base64Display` + `Display` | 无 → `String` | 只能物化 `String`；但**这不是性能瓶颈**（见 §6.1），只是签名约束 |

> 最后一条是本仓库的**签名命门**（原先误当性能命门）：Rust 有「不物化输出」的 API
> （`encode_slice` 直接写 `&mut [u8]`），而 MoonBit 侧 `Bytes → String` **不是解码而是重解释**
> （见 [§5.3](#53-string-是-utf-16字节与字符之间没有免费的桥)），因此输出形态必须在签名上定死。
> 但实测「批量物化」并不比逐字符快（[§6.1](#61-一处必须更正的量物化路径不是提速点)），
> 所以这条约束**不构成本项目的性能瓶颈**。

## 5. 实测：`wasm-gc` 上 `V128` 可用的边界

这是本次分析**唯一没有现成答案**的问题——官方 core 的 `encoding/base64` 把向量路径用
`#cfg(any(target="native", target="wasm"))` 排除在 `wasm-gc` 之外（见其 `encode.mbt` / `decode.mbt`），
本仓库 AGENTS.md 又禁止引入未验证的后端。所以先做实验。

### 5.1 实验方法与结果

编译一个最小探针包（`wasm-gc`），直接**解析产物 wasm 的 `0xFD` 前缀指令**统计。
复跑脚本见 [§7](#7-复跑方式)。

| 能力 | 判定 | 佐证 |
|------|:----:|------|
| `v128.const` | ✅ 有 | 出现 `0xFD 0x0C` |
| `i8x16.swizzle` | ✅ 有 | 出现 `0xFD 0x0E` |
| `i64x2.replace_lane` / `extract_lane` | ✅ 有 | 出现 `0xFD 0x1E` / `0xFD 0x1D` |
| 通用 `V128` 位运算（`v128_and_` / `v128_xor`） | ✅ 有 | 由 core 映射到原生指令 |
| `v128.load`（从 `FixedArray[Byte]`） | ❌ **未发出** | 见 §5.2 |
| `v128_load_i16x8`（从 `String`） | ❌ **未发出** | 见 §5.2 |

> **关键判别**：显式 `@v128` 调用 → 产物 9 条 `0xFD`；同一进程里的纯标量循环 → **0 条**。
> 出现 `0xFD` 即证明**不是** scalar fallback（降级实现不会产生该前缀）。

### 5.2 结论：有指令，缺装载

`wasm-gc` 上**没有线性内存**（`Bytes` 是 GC 数组），所以 Rust 那种「把切片当内存指针灌进向量寄存器」的路子不存在。

实测 `@v128.v128_load(FixedArray[Byte], 0)` 的产物指令分布是
`v128.const × 1`、`i64x2.extract_lane × 2`、`i64x2.replace_lane × 2`——**没有 `v128.load`（应为 `0xFD 0x0B`）**。
core 里它的实现正是把 8 个 `u8` 手工 `unsafe_get` 拼成 `u64`，再 `make(lo, hi)`（见其 `simd_memory.mbt`）。

而 `@v128.v128_load_i16x8(String, offset)` 在 `offset + 8 > s.length()` 时
**抛 `RuntimeError: array element access out of bounds`**（实测 `s.length() = 12`、`offset = 5`）——
`String` 没有「一次读 8 个 code unit 越过尾部」的安全语义。

**于是得到可执行的移植结论**：

1. **装载是唯一短板**：向量**运算**全有原生指令，向量**输入**要靠 lane 组装。
2. **装载成本可摊薄**：一次组装 16 字节，供后续多轮运算使用；或改「分块装载 → 批量运算 → 批量写回」的节奏。
3. **边界必须由库自己管**：不能依赖 `String` 侧的安全越界读，分块循环要以显式长度判断收尾。
4. **`wasm` 线性后端的对照价值有限**：它有 `v128.load`，但本仓库**不分发**该后端（`supported_targets = "+wasm-gc"`），
   故不能作为「先在 wasm 上做、再搬回 wasm-gc」的借口——**要从一开始就面向 `wasm-gc` 写**。

### 5.3 `String` 是 UTF-16：字节与字符之间没有免费的桥

这是上一版本文档**写错且会误导架构**的一条，单列更正。

**实测**（复跑见 [§7](#7-复跑方式)）：

```moonbit
"Zg==".length()                 // 4   —— 4 个 code unit
"中".length()                   // 1
@utf8.encode("Zg==").length()   // 4   —— 走 UTF-8 编码后是 4 字节（ASCII 恒等）
```

`String` 内部按 **UTF-16 code unit** 存储。注意 `to_bytes()` 已 deprecated，且它给出的是
**原始 code unit 的字节视图**（`b"Z\x00g\x00=\x00=\x00"`），不是 UTF-8 ——
所以**不要**用 `String::to_bytes()` 当「字符串的字节」用。

更要命的是**反方向**：把 `Bytes` 变成 `String` 的两条「捷径」都不做 ASCII 解码，而是按
**一对字节 = 一个 code unit** 重解释：

```moonbit
b"ABCDEFGH".to_unchecked_string()   // 结果 len = 4，内容为 "䉁䑃䙅䡇"（不是 "ABCDEFGH"）
let buf = Buffer::Buffer(); buf.write_bytes(b"ABCDEFGH"[:])
buf.to_string()                     // 同样 len = 4，重解释
buf.to_bytes()                      // b"ABCDEFGH"，len = 8（正确）
```

即：**`Bytes → String` 在 `wasm-gc` 上是一条「重解释」路，不是「解码」路**，
它只在「这些字节本来就是 code unit」时才成立。对 base64 的 ASCII 输出，这条路**恒错**。

**由此得到三条硬结论**：

1. **`String` 只能是输出终点，不能是中间缓冲。** 字节级处理一律在 `Bytes` / `FixedArray[Byte]` 上做，
   到交付时再逐 code unit 写入 `String`。
2. **唯一正确的 `Bytes → ASCII String` 构造是逐 `Char` 写**（`StringBuilder::write_char`
   或先建 `FixedArray[Char]` 再 `String::from_array`）。**没有「零拷贝 / 批量重解释」的捷径**——
   见 [§6](#6-复杂度评估按分层拆解) 实测：批量数组与逐字符两条路**速度相同**。
3. **`decode` 不能在 `String` 上做**：解码输入是「字节视图」，用 `String` 当入参等于
   先把字节塞进 UTF-16 再取出，语义与性能双输。详见
   [S2 §2.4](S2-现状基线与迁移缺口.md#24-签名决策decode-的入参返回与定长输出)。

> 这条更正推翻了本仓早期的三处写法（`String` 越界即 panic、`String` 当装载来源、
> 「定长 + reinterpret」是编码快路）。**前两处是前提错，第三处是量错**——见 §6。

## 6. 复杂度评估（按分层拆解）

评级尺度：**S** = 半天内可完成并验证；**M** = 数日；**L** = 需跨轮迭代 + 专门验证装置。

| 工作项 | 复杂度 | 主要风险 |
|--------|:-----:|---------|
| ① 标量内核 + 4 判据后缀校验 | **M** | 判据组合多（4 错误 × 3 padding 模式 × 冗余位开关），易漏 |
| ② 配置体系（padding / trailing bits / 错误定位） | **S** | 只有 API 形态选择问题 |
| ③ 引擎对象 + 表缓存 | **S** | 与「纯函数 API」的取舍 |
| ④ **签名决策**（`decode` 入参/返回 + 定长输出形态） | **M** | 决定 ①⑤ 的函数签名；先写实现再改形态 = 写两遍 |
| ⑤ **批量内核**（编码 4 字节展开 / 解码 4 字符展开） | **M** | 实测这才是真提速点（解码 1.6–2.0×），非物化路径 |
| ⑥ SIMD128 路径 | **L** | `wasm-gc` 上**不会自动向量化**；需自建 lane 装载 + 逐字节差分 |
| ⑦ 语义矩阵（长度全扫 × 配置叉积 × 与 Rust 对拍） | **L** | 这是**最重的一块**，也是最容易被跳过的一块 |
| ⑧ fuzz / 属性测试（roundtrip、随机配置） | **M** | 需先有 ① 的判据，否则 fuzz 只会重复发现同一类错 |

### 6.1 一处必须更正的量：物化路径**不是**提速点

上一版把「定长 `FixedArray` → 一次性转 `String`」列为性能项（预期 1.5–3×）。
本次用正确实现复测（等长循环、`wasm-gc`、`release`、取总时长，**输出与逐字符版逐字节相同**）：

| 编码实现（46 B / 4 KB / 136 KB） | MB/s（输入字节/秒） |
|---|---:|
| `StringBuilder::write_char` 逐字符 | 187 / 322 / 170 |
| `FixedArray[Char]` 批量填 + `String::from_array` | 209 / 306 / 152 |

**两条路速度相同（差异在噪声内），大输入下批量版甚至略慢。** 原因就是
[§5.3](#53-string-是-utf-16字节与字符之间没有免费的桥)：`String` 的构造必须逐 code unit 落地，
无论你把 code unit 先攒在数组里还是直接写 builder，**最终都要写一遍**——
「定长 + 批量」省下的不是拷贝，只是循环形态，而那个循环本来就不贵。

**真正有量级的是「批量处理」而不是「批量物化」**。解码侧实测（多出的是「4 字符 → 3 字节」展开）：

| 解码实现（88 B / 5.4 KB / 185 KB 输入） | MB/s（输入字节/秒） | 相对 |
|---|---:|---:|
| 逐字符累积 + `Buffer::write_byte`（现做法） | 275 / 433 / 298 | 1.0× |
| **4 字符 → 3 字节展开** | **550 / 728 / 488** | **1.6–2.0×** |

结论三条：

1. **物化路径要修的是「正确性」不是「速度」**：`decode` 的入参与返回形态必须落在
   `Bytes` / `FixedArray[Byte]` 上（否则撞 §5.3），这是**签名约束**；
2. **性能投入应放在批量内核（`⑤`）**：把「一次读 4 个符号」写出来，收益可复跑、可归因；
3. **不要再用「重解释捷径」测性能**：它测的不是同一件事（长度都变了），会得出虚假的 2–4×。

### 6.2 关键判断

`⑥` 是纯粹的性能工作，**按用户既定约束移出首版**；`①⑦` 是正确性工作，**必须先做**；
`④` 是前置——它决定 ①⑤ 的签名，先写实现再改形态等于写两遍。

性能顺序应修正为：**`④ → ①② → ⑤ → ⑦`**，`⑥⑧` 有条件再启。
理由：`⑤` 的量级（1.6–2.0×）已在本次实测中确认，而它**不依赖** SIMD、也不依赖物化改动，
是当前唯一「证据充分且可独立交付」的性能项。

## 7. 复跑方式

统一环境：MoonBit `0.1.20260920 (914d7da)`，`wasm-gc`，`--release`，`@env.now()` 取总时长
（毫秒精度，故**必须**用等长循环摊薄；单次测量无意义）。探针包建在 `/tmp`，**不入库**。

| 结论 | 复跑命令 / 步骤 |
|------|---------|
| 层级行数分布（§2） | 克隆 crate 后 `find . -name '*.rs' \| xargs wc -l \| sort -n` |
| 是否自动向量化（§3.5、§5.1） | 建最小 exec 包：先只放标量循环 → 统计产物 `0xFD`；再加 `@v128.i8x16_swizzle` 等 → 再统计 |
| 产物 SIMD 指令计数 | `python3 -c "d=open('<pkg>.wasm','rb').read(); print(d.count(b'\xfd'))"` |
| 是否发出 `v128.load`（§5.2） | 对 `v128_load(FixedArray[Byte],0)` 的产物解析 `0xFD` 后的 ULEB opcode，**不应出现 `11`** |
| `String` 越界读是否 panic（§5.2） | 对 `v128_load_i16x8(s, offset)` 传 `offset + 8 > s.length()`，观察 `RuntimeError` |
| `String` 是 UTF-16（§5.3） | `"Zg==".length()` / `"中".length()` / `@utf8.encode("Zg==").length()` |
| `Bytes → String` 是重解释而非解码（§5.3） | `b"ABCDEFGH".to_unchecked_string().length()` 应为 `4`；`Buffer::write_bytes` 后 `to_string().length()` 亦为 `4`，而 `to_bytes().length()` 为 `8` |
| 编码物化两条路同速（§6.1） | 同一输入跑「`StringBuilder` 逐字符」与「`FixedArray[Char]` + `String::from_array`」，比对总时长与输出相等性 |
| 解码批量展开的倍数（§6.1） | 同一 base64 输入跑「逐字符累积」与「4 字符展开」，比对总时长与输出长度 |
| 三后端可用性 | `moon build <pkg> --target {wasm-gc,wasm,native}`；注意 `native` 需系统 C 编译器 |
| 本仓库当前门禁基线 | `bash scripts/gates.sh` |

> 本文的**性能数字口径统一为「输入字节 / 秒」**。早期的「定长 + reinterpret」数字
> 因走 [§5.3](#53-string-是-utf-16字节与字符之间没有免费的桥) 的重解释路而**输出长度都不同**，
> 不属同一测量对象，已作废，不得引用。

## 8. 建议的迭代顺序

1. **先定签名**：按 [§5.3](#53-string-是-utf-16字节与字符之间没有免费的桥) 落定
   `decode` 入参（字节视图）/ 返回（`Bytes`）/ 定长输出（`FixedArray[Byte]`）。
   这一步不改行为，但它决定后面所有实现的形态。
2. **再补判据**：`decode` 落地「末尾 2~4 符号 + padding 模式 + 冗余位」三段校验，
   并给出 4 类可定位错误。**此步不改性能，只改可信度。**
3. **然后做批量内核**：编码 4 字节展开、解码 4 字符展开（实测解码 1.6–2.0×，
   见 [§6.1](#61-一处必须更正的量物化路径不是提速点)），并给出长度全扫差分。
4. **最后做语义矩阵**：长度全扫 + 配置叉积，并与 Rust crate 对拍（对拍产物不入库）。
5. **SIMD128 不进首版**：按用户既定约束（`wasm-gc` 单目标、暂不做向量化）搁置，
   恢复条件写在 [S2 §4](S2-现状基线与迁移缺口.md#4-迁移路线图可勾选) 的路线图备注里。

> 注意与上一版顺序的差别：**物化路径从「性能项」降级为「签名项」**（步骤 1，不是步骤 2 的性能工作），
> **批量内核从「可后置」升级为「当前唯一可交付的性能项」**（步骤 3）。依据是 §6.1 的实测。

## 9. 移植目标：API 兼容的边界（含 `no_std`）

本项目目标是**对 rust-base64 的 API 兼容移植**，因此需要一份明确的「兼容到什么程度」清单。
crate 自身的 `no_std` 分层正好给出了可对齐的边界（实测 `Cargo.toml` + `src/lib.rs`）：

```
default = ["std", "simd-unsafe"]
alloc   = []
std     = ["alloc"]              # std ⇒ alloc
simd-unsafe = []
#![cfg_attr(not(any(feature = "std", test)), no_std)]
```

| 档位 | 关掉什么 | 丢掉的能力 | 保留什么 |
|------|---------|-----------|---------|
| `std`（默认） | — | 无 | 全部，含 `read::DecoderReader` / `write::EncoderWriter` / `display::Base64Display` / `impl std::error::Error` |
| `+alloc`（`no_std` + 堆） | `default-features` 后加 `alloc` | `std::io` 流式层、`Base64Display`、`std::error::Error` 实现 | `Engine::{encode, encode_string, decode, decode_vec}` + `encode_slice` / `decode_slice` |
| `core`（`no_std` 无堆） | 只留 `core` | 上面全部，**再加 4 个分配型方法** | 只剩 slice 系：`encode_slice` / `decode_slice` / `decode_slice_unchecked` / `internal_*` / `Alphabet` / `Symbol` / 错误类型 |

**关键：`encode_slice` / `decode_slice` 不被 `alloc` 门控**（`src/lib.rs` 实测——
它们的 `#[cfg]` 上面没有 `alloc` gate）。也就是说 crate 的**零分配内核在 `core` 档是完整可用的**，
分配只是外面包了一层。

**对本项目的三点意义**：

1. **兼容对象 = `core` + `alloc` 两档的并集**，即「全部非流式公开 API」。
   流式层（`read` / `write` / `display`）不在兼容目标内，因为其载体是 Rust 的标准 trait。
2. **crate 自己就把「内核」与「物化」分开了**，MoonBit 应**照抄这个分层**：
   `lib/internal/` 放零分配内核（slice 进 slice 出），`lib/` 门面再做物化。
   这比把物化当性能项更贴合「API 兼容」的目标。
3. **8 个自由函数已 deprecated**（`#[deprecated(since="0.21.0")]`，实测见 `src/{encode,decode}.rs`）：
   `encode` / `encode_engine` / `encode_engine_string` / `encode_engine_slice` /
   `decode` / `decode_engine` / `decode_engine_vec` / `decode_engine_slice`。
   0.23 的对外口径是 **`Engine` trait 唯一入口**。它们**是兼容面，但不是 API 面**——
   首版**不必**实现，以免把已废弃的形态固化进本库。

> `Engine` 的公开方法实测为 8 个：`encode` / `encode_string` / `encode_slice` /
> `decode` / `decode_vec` / `decode_slice` / `decode_slice_unchecked` /
> `internal_decoded_len_estimate`（另 2 个 `internal_*` 为 `Engine` trait 的实现契约）。

## 10. 边界与不做什么

- **不移植流式层 trait 外壳**（`read` / `write` / `display`）：无对应 trait；
  `chunked_encoder` 的节律**可搬但优先级低**（见 [§3.4](#34-流式层f-层不可移植)）。
- **不实现 8 个 deprecated 自由函数**：兼容目标是 `Engine` 入口，不是历史 API。
- **不移植 AVX2 / NEON**：MoonBit 载体是 SIMD128；照搬 `_mm256_*` 是无效劳动。
- **不做运行时分发**：`wasm-gc` 无此必要，编译期决定即可。
- **不引入外部依赖**：本库定位是「纯 MoonBit、零依赖」，所有表与引擎自持。
- **不把 `.mbti` / 构建产物入库**：见 [AGENTS.md](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/AGENTS.md) §一。

## 11. 参考

- Rust crate 源码与变更史：`marshallpierce/rust-base64`（`src/engine/**`、`RELEASE-NOTES.md`）
- MoonBit 官方实现：`moonbitlang/core` 的 `encoding/base64`（`{encode,decode}{,_v128}.mbt`）
- SIMD128 语义参考：`moonbitlang/core` 的 `v128` 包
- 本仓库实测数据与性能分级：[ISSUE #3](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/issues/3)
- 本仓库工程约定：[AGENTS.md](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/AGENTS.md)
