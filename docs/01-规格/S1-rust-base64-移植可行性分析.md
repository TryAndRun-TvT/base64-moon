# S1 · rust-base64 移植至 MoonBit 的可行性分析

> **状态**：现行　｜　日期：2026-10-07　｜　索引：[docs/README.md](../README.md) §1

> 一句话结论：**移植可行，且值得做，但不是「照搬一个库」**。
> `base64` crate 真正可搬运的只有**标量内核**（约 600 行，含配置与错误语义）；
> 其余三块——`std::io` 流式层、AVX2/NEON 向量层、泛型 `Engine` trait——**在 MoonBit 里没有对应物或已被现行设计取代**。
> 本机实测已把最不确定的一环（`wasm-gc` 到底有没有真 SIMD）验证清楚：**有指令、缺装载**，
> 详见 [§5](#5-实测wasm-gc-上-v128-可用的边界) 与 [§6](#6-复杂度评估按分层拆解)。

## 0. 本文的范围与证据口径

- **被研究对象**：`marshallpierce/rust-base64`，本地克隆于 `5b98ee1`（2026-08-18），版本 `0.23.1`。
- **对照对象**：`moonbitlang/core` 的 `encoding/base64`（本地克隆于 `90558a3`，2026-10-07），
  以及本仓库骨架 `lib/base64.mbt`。
- **本机实测**：MoonBit `0.1.20260920 (914d7da)`、`moonc` 同版本；`wasm-gc` / `wasm` / `native` 三后端。
- **口径纪律**：本文每个数字都附**复跑方式或出处**；无法复跑的口径一律标注「引自官方源码」。
  性能数字**不在本文**——见 [ISSUE #3 实测结论](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/issues/3)，
  本文只做**结构与复杂度**判定。

## 1. 结论速览

| 被移植物 | 体量 | MoonBit 可行性 | 建议 |
|---------|------|:--------------:|------|
| 标量编解码内核（`general_purpose` + 后缀校验） | ≈ 600 行 | ✅ 直接可搬 | **做**：本仓库的主战场 |
| 配置与错误语义（3 配置项 / 4 错误变体 / 3 padding 模式） | ≈ 200 行 | ✅ 可直接搬 | **做**：这是与官方实现拉开差距的关键 |
| 字母表体系（`Symbol` / `Alphabet` / 6 张预置表 / 自定义 padding） | 404 行 | ⚠️ 可搬，需重设计 | **做**：把「表」从 `const` 变成构造期生成 |
| 零拷贝输出与「就地编解码」API 形态 | `encode.rs` + `decode.rs` 共 929 行 | ✅ 可搬（且是性能关键） | **做**：`wasm-gc` 的 `Bytes` 是 GC 数组，切片语义与 Rust `&mut [u8]` 可对齐 |
| `std::io` 流式层（`read` / `write` / `chunked_encoder` / `display`） | 1219 行 | ❌ 无对应物 | **不做**：MoonBit 无 `io::Read`/`io::Write` trait |
| AVX2 / NEON 向量层 | 807 行 | ❌ 无对应物 | **不做**：取而代之，用 `V128` 写 SIMD128 |
| `Engine` trait + `Simd` 运行时分发 | 516 + 807 行（已计入上两行） | ⚠️ 形态可借鉴，机制不适用 | **部分借鉴**：trait object 可用，但运行时分发在 wasm-gc 无意义 |
| 测试矩阵（`engine/tests.rs` 2182 行 + 三处 `*_tests.rs`，rstest 参数化全引擎遍历） | 3364 行 | ⚠️ 需换形态 | **借鉴判据，不搬框架**：MoonBit 无 rstest，用「差分 + 长度全扫」替代 |

**一句话**：crate 的 9600 行 Rust 里，**可搬运约 31%**（A/C/D/E 层的实现，≈ 2950 行中约 70% 可直接落），
**必须重设计约 19%**（`Engine` 抽象、表缓存、SIMD128 重写），**不要搬约 46%**（F 流式层 + B 层 x86/ARM 内建函数），
**必须换形态约 35%**——但最后这块（`G`/`H` 测试与基准）**恰恰是最该学、最不该省的部分**。
复杂度**不在算法**——算法是中学生的位运算；复杂度在**语义完整性**（4 判据）与**输出物化路径**。

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
`chunked_encoder.rs`（`Sink` trait）、`display.rs`（`Display` trait）四者合计 1219 行，全部依赖 Rust 的两个标准 trait。

**MoonBit 目前没有对应的 IO trait 抽象**，硬造一个等于自建封闭生态，与「纯库、零依赖」的项目定位冲突。
结论：**不做**。若将来宿主需要流式场景，正确做法是在宿主侧按同样的「整块 + 尾块」节奏调用本库的 slice API。

### 3.5 向量层（B 层）——机制不可搬，目标可搬

crate 的 `simd.rs` 用 `#[target_feature(enable = "avx2")]` + `_mm256_*` 内建函数，
再加 `std::is_x86_feature_detected!` 做运行时分发。MoonBit 侧**三点都不对应**：

- 无 `#[target_feature]`：`wasm-gc` 要么全量编译出 SIMD 指令（实测确实会），要么没有；
- 无 x86/ARM 内建函数：MoonBit 的载体是 SIMD128（`V128`），**128 位一条**，而非 256 位一条；
- 无运行时分发必要：`wasm-gc` 的目标是单一代（Wasm GC 提案），SIMD128 在同代里是**默认假定可用**的。

结论：**不是「搬 AVX2 代码」，而是「用 SIMD128 重写同样三件事」**——
① 6 位值 ↔ ASCII 的位运算映射；② 无效字符的向量化检出；③ 装载与「1024 字节块」的分块。

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
| 惰性输出 | `Base64Display` + `Display` | 无 → `String` | 只能物化 `String`，故**物化路径是性能关键** |

> 最后一条是本仓库的性能命门：Rust 有「不物化输出」的 API（`encode_slice` 直接写 `&mut [u8]`），
> 而 MoonBit 要得到 `String` 必须走一次 UTF-16 物化。这与
> [ISSUE #3 实测](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/issues/3) 指出的
> 「官方 `encode` 4.4 ms 里算术只占 0.19 ms」是同一个问题。

## 5. 实测：`wasm-gc` 上 `V128` 可用的边界

这是本次分析**唯一没有现成答案**的问题——官方 core 的 `encoding/base64` 把向量路径用
`#cfg(any(target="native", target="wasm"))` 排除在 `wasm-gc` 之外（见其 `encode.mbt` / `decode.mbt`），
本仓库 AGENTS.md 又禁止引入未验证的后端。所以先做实验。

### 5.1 实验方法与结果

在 `wasm-gc` / `wasm` 两个后端各编译一个最小探针包，直接**解析产物 wasm 的 `0xFD` 前缀指令**统计。
复跑脚本见 [§7](#7-复跑方式)。

| 能力 | `wasm`（线性内存） | `wasm-gc` | 判定 |
|------|:-----------------:|:---------:|------|
| `v128.const` | ✅ 有 | ✅ **有** | 编译期向量常量可用 |
| `i8x16.swizzle` | ✅ 有 | ✅ **有** | 查表类向量操作可用 |
| `i8x16.shuffle` | ✅ 有 | 未直接测到 | 与 swizzle 同族，预期可用 |
| `i64x2.replace_lane` / `extract_lane` | ✅ 有 | ✅ **有** | lane 组装/拆解可用 |
| `v128.load`（从 `FixedArray[Byte]`） | ✅ 有 | 未发出 | 见 §5.2 |
| `v128_load_i16x8`（从 `String`） | 待测 | 未发出 | 见 §5.2 |
| 通用 `V128` 位运算是**单指令** | — | ✅ 已证 | `v128.and/or/xor/bitselect/any_true` 由 core 直接映射 |

> **实测指令清单**（`wasm-gc` 产物）：`v128.const`、`i8x16.swizzle`、`i16x8.extract_lane_u`、
> `i64x2.replace_lane`、`i64x2.extract_lane`。**不是 scalar fallback**——
> 若是降级实现，产物里不会出现 `0xFD` 前缀指令。

### 5.2 结论：有指令，缺装载

`wasm-gc` 上**没有线性内存**（`Bytes` 是 GC 数组），所以 Rust 那种「把切片当内存指针灌进向量寄存器」的路子不存在。
实测 `@v128.v128_load(FixedArray[Byte], offset)` 在 `wasm-gc` 上**不报错但也不是单条 `v128.load`**：
core 里它的实现是把 8 个 `u8` 手工 `unsafe_get` 拼成 `u64`，再 `make(lo, hi)`。
而 `@v128.v128_load_i16x8(String, offset)` **越界即 panic**（实测 `offset=4`、`s.length()=11` 时
抛 `RuntimeError: array element access out of bounds`）——因为 `String` 没有「一次读 8 个 code unit
越过尾部」的安全语义。

**于是得到可执行的移植结论**：

1. **装载是唯一短板**：向量**运算**全有原生指令，向量**输入**要靠 lane 组装。
2. **装载成本可摊薄**：一次组装 16 字节，供后续多轮运算使用；或改「分块装载 → 批量运算 → 批量写回」的节奏。
3. **边界必须由库自己管**：不能依赖 `String` 侧的安全越界读，分块循环要以显式长度判断收尾。
4. **`wasm` 线性后端的对照价值有限**：它有 `v128.load`，但本仓库**不分发**该后端（`supported_targets = "+wasm-gc"`），
   故不能作为「先在 wasm 上做、再搬回 wasm-gc」的借口——**要从一开始就面向 `wasm-gc` 写**。

## 6. 复杂度评估（按分层拆解）

评级尺度：**S** = 半天内可完成并验证；**M** = 数日；**L** = 需跨轮迭代 + 专门验证装置。

| 工作项 | 复杂度 | 主要风险 |
|--------|:-----:|---------|
| ① 标量内核 + 4 判据后缀校验 | **M** | 判据组合多（4 错误 × 3 padding 模式 × 冗余位开关），易漏 |
| ② 配置体系（padding / trailing bits / 错误定位） | **S** | 只有 API 形态选择问题 |
| ③ 引擎对象 + 表缓存 | **S** | 与「纯函数 API」的取舍 |
| ④ 输出物化路径（定长 `FixedArray` → 一次性转 `String`） | **M** | 影响所有 API 形态，改动面大；跨 JS/宿主边界的行为要另测 |
| ⑤ SIMD128 编码路径（swizzle 位运算） | **L** | 需自建 lane 装载；需与标量路径**逐字节差分** |
| ⑥ SIMD128 解码路径（完美哈希分类 + 有效性检出） | **L** | 同上；且无效字符定位要回退标量报告精确 offset |
| ⑦ 语义矩阵（长度全扫 × 配置叉积 × 与 Rust 对拍） | **L** | 这是**最重的一块**，也是最容易被跳过的一块 |
| ⑧ fuzz / 属性测试（roundtrip、随机配置） | **M** | 需先有 ① 的判据，否则 fuzz 只会重复发现同一类错 |

**关键判断**：`⑤⑥` 是纯粹的性能工作，**可以后置**；`①⑦` 是正确性工作，**必须先做**。
按 [ISSUE #3 实测](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/issues/3)，
仅做 `①④` 两条（重写标量 + 修物化路径）就能拿到 1.5–3 倍；`⑤⑥` 的收益是再一个数量级，
但**前提是 ① 已经是可信基线**，否则拿一个不确定的实现去比性能没有意义。

## 7. 复跑方式

| 结论 | 复跑命令 |
|------|---------|
| 层级行数分布（§2） | 克隆 crate 后 `find . -name '*.rs' \| xargs wc -l \| sort -n` |
| `wasm-gc` 是否有真 SIMD 指令（§5.1） | 建最小探针包调 `@v128.i8x16_swizzle`，编译 `--target wasm-gc`，解析产物 `0xfd` 前缀 |
| `String` 越界读是否 panic（§5.2） | 对 `v128_load_i16x8(s, offset)` 传 `offset + 8 > s.length()`，观察 `RuntimeError` |
| 三后端可用性 | `moon build <pkg> --target {wasm-gc,wasm,native}`；注意 `native` 需系统 C 编译器 |
| 本仓库当前门禁基线 | `bash scripts/gates.sh` |

> 本文的性能分级**不在此处复现**，权威出处为
> [ISSUE #3 的实测评论](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/issues/3)。

## 8. 建议的迭代顺序

1. **先把判据补齐**：`decode` 落地「末尾 2~4 符号 + padding 模式 + 冗余位」三段校验，
   并给出 4 类可定位错误。**此步不改性能，只改可信度。**
2. **再修物化路径**：定长输出缓冲 + 一次性转 `String`，把引擎与表做成可复用值。
3. **然后才是 SIMD128**：按 [§5.2](#52-结论有指令缺装载) 的四条约束写分块路径，
   与标量路径做**逐字节差分**（所有长度、两个字母表、两种 padding）。
4. **最后做语义矩阵**：长度全扫 + 配置叉积，并与 Rust crate 对拍（对拍产物不入库）。

## 9. 边界与不做什么

- **不移植流式层**（`read` / `write` / `chunked_encoder` / `display`）：无对应 trait，收益不成比例。
- **不移植 AVX2 / NEON**：MoonBit 载体是 SIMD128；照搬 `_mm256_*` 是无效劳动。
- **不做运行时分发**：`wasm-gc` 无此必要，编译期决定即可。
- **不引入外部依赖**：本库定位是「纯 MoonBit、零依赖」，所有表与引擎自持。
- **不把 `.mbti` / 构建产物入库**：见 [AGENTS.md](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/AGENTS.md) §一。

## 10. 参考

- Rust crate 源码与变更史：`marshallpierce/rust-base64`（`src/engine/**`、`RELEASE-NOTES.md`）
- MoonBit 官方实现：`moonbitlang/core` 的 `encoding/base64`（`{encode,decode}{,_v128}.mbt`）
- SIMD128 语义参考：`moonbitlang/core` 的 `v128` 包
- 本仓库实测数据与性能分级：[ISSUE #3](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/issues/3)
- 本仓库工程约定：[AGENTS.md](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/AGENTS.md)
