# bench · 外部对照基准（口径与用法）

> **状态**：现行　｜　日期：2026-10-08　｜　索引：[docs/README.md](../docs/README.md) §6

> 面向：**要复跑性能数字的人** / **要改这个框架的人**。
> 本文件只讲**口径与结构**；实测数字与结论见
> [docs/02-证据/E1-外部对照基线.md](../docs/02-证据/E1-外部对照基线.md)。

---

## 0. 这个目录在解决什么问题

本仓此前**零**性能探针入库：每个数字都是「临时 `*_wbtest.mbt`，跑完即删」。
代价不是没数字，而是**三次性能翻车全部是口径问题**，不是算法问题：

| 翻车 | 性质 | 出处 |
|------|------|------|
| S6 的「27%」 | 分子分母不同层 | [S6 §1](../docs/01-规格/S6-性能实测与M3裁决.md) |
| S7 的「0.78×」 | 单次直测 + 跨轮漂移 | [S7 §6](../docs/01-规格/S7-M4性能前提复跑与裁决.md) |
| S9 的误读 | 对照层选错 | [S9 §3.3](../docs/01-规格/S9-M5语义矩阵与32位装载裁决.md) |

`bench/` 把「每次手写探针时的心智负担」变成**脚本里的五条纪律**（§2）。
它不改善绝对值，但它降低「下一轮又量错」的概率。
定位对应 [S10 §6.2](../docs/01-规格/S10-去内循环落地与端到端对照.md) 的**优先级 B**。

---

## 1. 目录结构

```
bench/
├── moon.work          # workspace：成员 = 主仓(..) + ./moonbit + ./size
├── cases.json         # 尺寸集 / 轮次 / 判据（唯一事实源，别在脚本里写死）
├── run.mjs            # 主程序：校验 → 往返计时 → **分向计时** → 出 JSON
├── report-size.mjs    # 体积报告（独立入口，见 §5）
├── results.json       # 计时产物（构建产物，不入库）
├── README.md          # 本文件
├── moonbit/           # MoonBit 侧 harness
│   ├── moon.mod       #   独立模块，路径依赖主仓
│   └── cmd/harness/   #   pkgtype = foreign_library，见 §3
├── rust/              # rust-base64 对照（base64 =0.23.1，精确钉版）
├── js/                # JS 对照（base64-js / js-base64 / node Buffer）
│   ├── package.json   #   钉死版本
│   ├── impls.mjs      #   各实现：同数据式、同校验和式
│   ├── driver.mjs     #   **唯一计时器**（hrtime.bigint）
│   └── size.mjs       #   体积测量工具
└── size/              # 体积探针（空 exec / 本库 / core 三个 executable）
```

**三个被测量（往返 / 编码 / 解码）**：`run.mjs` 出三类表——
**往返**（encode + decode，6 家横向可比）、**编码**、**解码**（后两者是分向，
让「哪条腿慢」可引用，见 [E2](../docs/02-证据/E2-编解码分向性能与根因.md)）。
分向**不相减**推往返（各自独立计时，只量级互校）。

**为什么是独立 workspace 而不是塞进 `lib/`**：

- 探针**不得扩公共面**（`.mbti` 会漂）——[S9 §1.3](../docs/01-规格/S9-M5语义矩阵与32位装载裁决.md) / [S5 §3.5](../docs/01-规格/S5-实施裁决与M1落地.md)；
- `moon.work` 成员用**相对路径** `..` 指主仓（workspace 里 registry 查不到 dev 版本，路径依赖是唯一接法）；
- 产物（wasm / node_modules / target）按 [AGENTS.md §一](../AGENTS.md) 禁入库，独立目录便于整棵排除。

**注意**：`moon.work` / `moon.mod` **不解析注释**——说明一律写在本文件，不要写进那两个文件。

---

## 2. 口径五条（本框架的全部价值所在）

| # | 纪律 | 落地在哪 | 防的是哪次翻车 |
|:-:|------|---------|--------------|
| ① | **数据在被测侧生成**（同一 seed 派生） | 各侧 `det_bytes`/`det`/`detBytes` 同式 | 跨语言对比的头号假象：比数据搬运 |
| ② | **计时器唯一**（Node `hrtime.bigint`） | `js/driver.mjs` 是唯一使用者；各侧只做纯计算 | 各家 bench 框架计时精度不同 |
| ③ | **交错 A/B + 中位数 + min/p50/max** | `interleaved()`；`cases.json` 的 `rounds` | [S7](../docs/01-规格/S7-M4性能前提复跑与裁决.md) 的 0.78× 跨轮漂移 |
| ④ | **防 DCE**：结果必须被读回 | 各出口回传校验和 / 长度累加值 | [S6 §6.1](../docs/01-规格/S6-性能实测与M3裁决.md) 的「整段被删掉」 |
| ⑤ | **报告必带尺寸 + 平台限定** | `run.mjs` 输出 `meta`（node / cpu / 后端 / 口径） | [S2 §5](../docs/01-规格/S2-现状基线与迁移缺口.md) 的「不可混比」 |

**①为什么是承重墙**：`wasm-gc` 的 `Bytes` 是 GC 数组、**没有线性内存指针**，
无法从 Node 灌入大 buffer（见 §3）。**数据必须由被测侧自己造**，否则量的是数据搬运。

**③为什么必须交错**：不交错就会把「前 10 秒机器凉、后 10 秒机器热」记成实现差异。
交错让漂移均摊到**所有**实现上，而不是单向流向某一个。

**④为什么不能省**：没有回传读回，`lto = true` + `--release` 会把整个被测段删掉，
量到的是「删掉代码有多快」。

### 2.1 分向出口（往返之外的两个被测量）

| 方向 | MoonBit 出口 | Rust 出口 | JS 出口 |
|------|-------------|-----------|---------|
| 往返 | `bench_roundtrip` | `bench_roundtrip` | `impls[].roundtrip` |
| **编码** | `bench_encode_only` | `bench_encode_only` | `impls[].encodeE2E` |
| **解码** | `bench_decode_only` | `bench_decode_only` | `impls[].decodeE2E` |
| （core 对照） | `bench_core_encode_only` / `bench_core_decode_only` | — | — |

**为什么分向不相减**：`encode` 与 `decode` 各自都含「建引擎 / 分缓冲 / 物化」，
相减会把共有常数项算错两次。故三段**各自**预热、交错、取中位数，只在量级上互校。

**JS 侧解码的输入**：必须是被测侧**自己编出**的合法 base64（与 harness / Rust 同源），
否则比的是「不同输入的容错路径」。

---

## 3. why `foreign_library` + 跨界只走 `Int`

**`foreign_library` 而非 `executable`**：实测 `executable` + `#export_name` 报 `[4219]`，
且会强制生成 `_start`。`foreign_library` 无入口、无 `_start`，
产物里**只有显式导出**的函数——正合基准所需。

**跨界只走 `Int`**：`wasm-gc` 的 `String` / `Bytes` 是 GC 对象，Node 侧**取不出内容**
（实测 `Object.keys(s)` 为空、无 `length` 可读）。故跨界只有两类值：

- `Int` 参数 / 返回值 —— 直传；
- 「输出写进被测侧自己的缓冲」—— 用**校验和** `Int` 回传。

这条顺带保证了纪律 ①（数据在被测侧生成），且 harness **不用 `println`** ⇒
产物**没有任何宿主导入**（`WebAssembly.Module.imports` 为空），少一处两侧不一致。

---

## 4. 一致性校验：先证明各家在算同一件事

计时之前，`run.mjs` 会对 13 个尺寸比对**编码串校验和 + 往返校验和**，
五家（base64-moon / rust-base64 / base64-js / js-base64 / node Buffer）**逐位相同**才算过。

**这是框架的承重墙**：没有它，后面所有数字都可能是「各自算了不同的东西」。
它已经真的抓到过一个 bug——JS 侧把 `new Uint8Array(str, "base64")` 的第二个参数
当成了编码（实为 length），跨实现校验和立刻指出来（见证据篇 §5.2）。

---

## 5. 体积口径（为什么用增量、为什么分组）

- **增量**：`引入这一家后 exec 大了多少字节`，相对「空 wasm-gc exec」。
  绝对值里绝大部分是**运行时**（GC、字符串原语），各实现共有，比它没意义。
- **raw + gzip -9 都报**：分发走压缩体积，但两者排序不一定一致。
- **分组、组间不比倍数**：
  - MoonBit 组（本库 vs core）—— 同运行时，**最干净**；
  - Rust 组 —— 没有 GC 运行时，仅参照；
  - JS 组 —— 报的是**源码**不是产物，不同量纲，仅参照。
- `gzip` 对 <200 B 文件会**变大**（gzip 头开销），基线行 `gzip > raw` 属正常。

---

## 6. 复跑

```bash
bash scripts/bench.sh                # 全量：校验 + 计时 + 体积（分钟级）
bash scripts/bench.sh --verify-only  # 只校验（秒级）
SKIP_RUST=1 bash scripts/bench.sh    # 无 rustup 时
SKIP_SIZE=1 bash scripts/bench.sh    # 跳过体积段
```

**前置（三运行时，一键）**：

```bash
bash scripts/setup-bench-runtimes.sh              # MoonBit + Rust + Node 全装
# 或分装：setup-moonbit.sh / setup-rust.sh / setup-node.sh
# 或只缺 Rust：SKIP_RUST=1 bash scripts/setup-bench-runtimes.sh
```

- `moon` + `node`（必需）；
- `cargo`/`rustc` + `rustup target add wasm32-unknown-unknown`（Rust 段，见 `scripts/setup-rust.sh`）；
- Node ≥ 20（计时器 + JS 侧对照，见 `scripts/setup-node.sh`）。

**退出码**：`0` = 全绿；`1` = 跨实现校验失败（数字无意义）；`2` = 工具链缺失。

**bench 不进 `gates.sh` 默认阶段**：它需要 Node + rustup + cargo + npm，分钟级，
挂进门禁会让「改一行注释」也付分钟级代价。要走门禁，只能挂成可独立跳过的阶段。

---

## 7. 负向验证（先证明能红）

框架自身也要能红（[AGENTS.md §三.2 铁律 5](../AGENTS.md)）。两种注入实测：

| 注入 | 结果 |
|------|------|
| Rust 侧编码首字符改掉（模拟实现算错） | **13 条红**，直指 `rust-base64` |
| MoonBit 侧数据式 `+1`（模拟两侧输入不同） | **红**，直指 `base64-moon` 为离群者 |

改回即绿。取证过程与输出见证据篇 §5。

---

## 8. 边界（本框架不做什么）

- **不做绝对时间线**：全部是**同机相对量**；跨机 / 跨次对比无效（无绝对值承诺）。
- **不比不同层**：内核段（`*_slice`）只在 MoonBit vs Rust 之间比；
  JS 侧没有「零分配内核」这一层，比了就是不同层。
- **不用 `native` 后端**：`wasm-gc` 与 native 内存模型不同；且
  [AGENTS.md §二.3](../AGENTS.md) 明确 native 不得进门禁。
- **不自动重试 / 不自动剔除离群点**：min/p50/max 三值原样报出，剔除是读数字的人的判断。
