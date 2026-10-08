# TryAndRun-TvT/base64-moon

> 基于 [MoonBit](https://www.moonbitlang.cn/) 的 Base64 编解码库（RFC 4648）。
> 纯 MoonBit 实现、无外部依赖。

[![mooncakes](https://cnb.cool/svg/badge/mooncakes?message=TryAndRun-TvT%2Fbase64-moon&color=blue)](https://mooncakes.io/docs/TryAndRun-TvT/base64-moon)
[![star](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/badge/star)](https://cnb.cool/tryandrun/moonbit_dev/base64-moon)
[![fork](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/badge/fork)](https://cnb.cool/tryandrun/moonbit_dev/base64-moon)
[![latest release](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/badge/release)](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/releases)
[![license](https://cnb.cool/svg/badge/license?message=Apache-2.0&color=green)](./LICENSE)

**项目状态**：骨架阶段（配置与工程约定已就位，实现待落地）。

| | |
|---|---|
| **语言** | [MoonBit](https://www.moonbitlang.cn/)（**仅 `wasm-gc`**） |
| **标准** | RFC 4648（标准表 + URL-safe 表，含/不含 padding） |
| **许可** | [Apache-2.0](LICENSE) |
| **测试** | 黑盒 / 白盒分层　→ [文档索引](#文档索引) |

> 本页是**落地页**：只给「能做什么 / 怎么用 / 边界在哪 / 去哪看细节」。
> **数字、参数、实验设计与历史记录**一律在 [`docs/`](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/README.md)，
> 本页的每条结论都带出处链接。

---

## 目录

- [功能特性](#功能特性)
- [快速开始](#快速开始)
- [构建与运行](#构建与运行)
- [文档索引](#文档索引)
- [项目结构](#项目结构)
- [工程约定与贡献](#工程约定与贡献)
- [License](#license)

---

## 功能特性

- **纯 MoonBit 实现**，无外部依赖，可直接 `moon add` 依赖到你的项目。
- **标准合规**：RFC 4648 —— 标准字母表（`+` / `/`）与 URL-safe 字母表（`-` / `_`），含/不含 padding 都可编。
- **编码 + 解码**：`encode` 默认输出带 `=` 填充的标准串（`padding=false` 可省）；`decode` 默认按 `RequireCanonical` 校验 padding，错误**带 offset**。
- **单一后端产物**：仅 `wasm-gc`（体积小、性能好；宿主需支持 GC 提案）。

> **实现状态**：**骨架阶段**。已落地 `encode` / `decode` 与字母表变体（测试覆盖 RFC 4648 官方向量），
> 完整的 API 细节与实现规格篇目待补齐（见 [docs/README.md §1](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/README.md#1-实现规格)）。

## 快速开始

在项目根目录（`moon.mod` 所在处）添加本库为依赖：

```bash
moon add TryAndRun-TvT/base64-moon
```

在 `moon.pkg` 中声明依赖（本库包路径为 `.../lib`，别名默认即目录名 `lib`）：

```toml
import {
  "TryAndRun-TvT/base64-moon/lib",
}
```

然后即可编解码——下面的示例**由门禁真编译真运行**（`mbt check` 文档测试），
可运行版本另见 [`cmd/main/main.mbt`](cmd/main/main.mbt)（`moon run cmd/main`）。

```mbt check
///|
test "readme_quick_start" {
  let bytes = b"foobar"
  assert_eq(@lib.encode(bytes), "Zm9vYmFy")
  @lib.expect_decoded(@lib.decode(b"Zm9vYmFy"[:]), bytes)
  // URL-safe 字母表：`+` / `/` 换成 `-` / `_`
  assert_eq(
    @lib.encode(b"\xfb\xff", alphabet=@lib.Alphabet::url_safe()),
    "-_8=",
  )
  // 无 padding 形态（URL-safe 场景惯例）
  assert_eq(@lib.encode(b"foob", padding=false), "Zm9vYg")
  // 解码错误可定位：offset + 出错字节
  @lib.expect_invalid_byte(@lib.decode(b"Zm9v!"[:]), 4, 33)
}
```

> 公共 API 一览以 `moon info` 的 `.mbti` 为准。

---

## 构建与运行

先安装 MoonBit 工具链：

```bash
curl -fsSL https://cli.moonbitlang.cn/install/unix.sh | bash
export PATH="$HOME/.moon/bin:$PATH"
```

模块根不设包（core 式布局）：库包在 `lib/`，CLI 在 `cmd/main/`，构建需显式给包名。

```bash
moon build lib                    # 编译库包
moon build cmd/main --release     # 编译 CLI（唯一后端 wasm-gc）
moon test                         # 运行单元/文档测试
```

提交前**必须**跑一次本地一键门禁（**未启用 push CI**）：

```bash
bash scripts/gates.sh                 # 全量；支持 STAGES="check test" / SKIP_SLOW=1
```

> 门禁阶段清单与脚本用途见 [AGENTS.md](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/AGENTS.md) §二.4。

---

## 文档索引

> **本页只保留落地页所需的入口**；面向本仓库读者的完整导航在
> [`docs/README.md`](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/README.md)；
> 面向**发布归档读者（mooncakes 落地页）**的链接一律用**仓库绝对链接**（见文末「链接约定」）。

| 我想… | 去哪 |
|-------|------|
| **刚接手这个仓库** | [仓库初始化配置说明](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/03-过程/仓库初始化配置说明.md)（配置来源与落地过程） |
| **改代码 / 提 PR** | [AGENTS.md](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/AGENTS.md)（**硬性约定**） |
| **定实现方案 / 评估工作量** | [S1 可行性分析](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/01-规格/S1-rust-base64-移植可行性分析.md)（**API 兼容边界 + `no_std` 分档**）→ [S2 现状基线与迁移缺口](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/01-规格/S2-现状基线与迁移缺口.md)（**签名决策 + 路线图**）→ [S5 实施裁决](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/01-规格/S5-实施裁决与M1落地.md)（**实测真值**）→ [S6 性能实测与 M3 裁决](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/01-规格/S6-性能实测与M3裁决.md)（**M3 性能真值**）→ [S7 M4 性能前提复跑与裁决](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/01-规格/S7-M4性能前提复跑与裁决.md)（**M4 性能真值**） |
| **看代码该写在哪个文件** | [S3 架构分层与子包职责](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/01-规格/S3-架构分层与子包职责.md)（**三层分层 + 子包职责表 + 思维导图**） |
| **动手写 M0–M5 的代码** | [S4 实施规格与落地顺序](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/01-规格/S4-实施规格与落地顺序.md)（**每阶段动作清单 + 判据矩阵 + 复跑命令 + 回退条件**） |
| **看实测真值与裁决** | [S5 实施裁决与 M1 落地](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/01-规格/S5-实施裁决与M1落地.md)（**crate 对拍真值表 + S4 与实测冲突处 + MoonBit 包边界约束**） |
| **看 M5 落了什么** | [S9 M5 语义矩阵与 32 位装载裁决](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/01-规格/S9-M5语义矩阵与32位装载裁决.md)（**四条不变量 + CPython 定值对拍、待测项结清**） |
| **看性能线收口到哪** | [S10 「去内循环」落地与端到端对照](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/01-规格/S10-去内循环落地与端到端对照.md)（**差分基线 + 合并判错、内核 1.37× / 端到端 1.29×、后续规划**） |
| **要比外部实现 / 复跑外部对照** | [E1 外部对照基线](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/02-证据/E1-外部对照基线.md)（**本库 vs Rust / JS / node Buffer / MoonBit core 的实测 + 口径五条 + 负向验证**）→ [bench/README.md](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/bench/README.md)（**框架结构 + 复跑方式**） |
| **看性能数字 / 想复跑** | [S6 性能实测与 M3 裁决](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/01-规格/S6-性能实测与M3裁决.md)（**建表占比、引擎复用收益、738 例对拍、过期口径清账**）→ [S7 M4 性能前提复跑与裁决](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/01-规格/S7-M4性能前提复跑与裁决.md)（**M4 的 chunk 化为什么不做**）→ [S9 M5 语义矩阵与 32 位装载裁决](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/01-规格/S9-M5语义矩阵与32位装载裁决.md)（**M5 语义矩阵、32 位装载零收益**）→ [S10 「去内循环」落地与端到端对照](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/01-规格/S10-去内循环落地与端到端对照.md)（**去内循环已落、内核/端到端两组数字**） |
| **看文档全量清单** | [docs/README.md](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/README.md)（目录首页 + 生成式清单） |
| **配置从哪来** | [仓库初始化配置说明 §2](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/docs/03-过程/仓库初始化配置说明.md#2-实现记录)（逐路径对照表） |

### 链接约定（摘要）

发布归档（mooncakes）**只收录随包分发面**（`README.md` / `LICENSE` / `lib/**` / `cmd/main` 等），
`.moonignore` 排除 `/docs/` 与 `/AGENTS.md`。故本页规则是：**归档内目标用相对链接；
`docs/**` 与 `AGENTS.md` 一律用仓库绝对链接**（`https://cnb.cool/.../-/blob/main/...`）。
本页**不含**任何 `./docs/**` 相对链接（否则归档读者必 404）。完整纪律见
[AGENTS.md](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/AGENTS.md) §四。

---

## 项目结构

```
.
├── moon.mod                    # MoonBit 模块配置
├── moon.pkg                    # 模块根空包：README 文档测试宿主（不写库代码）
├── lib/                        # 公共 API 外壳（物化 + 默认引擎）
│   ├── facade.mbt              #   对外 pub API
│   └── internal/               # 零分配内核（不反向依赖 lib）
│       ├── alphabet.mbt         #   字母表结构（64 符号 + padding）
│       ├── tables.mbt           #   编码表 / 反查表构造
│       ├── config.mbt           #   padding / 冗余位 / padding 强度
│       ├── error.mbt            #   suberror DecodeError（4 类可定位）
│       ├── engine.mbt           #   Engine：表缓存
│       ├── encode.mbt           #   编码内核（slice 进 slice 出，不写 padding）
│       ├── pad.mbt              #   补 padding（全库唯一写 `=` 的地方）
│       └── decode.mbt           #   解码内核（4 判据 + 后缀校验）
├── cmd/main/                   # 可执行包：CLI
├── docs/                       # 项目文档（入口 = docs/README.md，见「文档索引」）
│   ├── README.md               #   目录首页：读者路径 + 分类地图 + 全量清单
│   └── 01-规格/ 02-证据/        #   D2 分类：实现规格 / 审计数据
│      03-过程/ 04-元/          #   D2 分类：历史基线+发布过程 / 文档与 README 元规范
├── scripts/                    # 构建/门禁脚本（按角色分组）
├── .githooks/ .cnb.yml         # 可选 Git 钩子 / 云原生构建配置
├── .vscode/                    # 编辑器推荐扩展与约定
├── AGENTS.md                   # AI 协作代理指南（贡献前必读）
├── README.mbt.md -> README.md  # 文档测试入口（符号链接；正文在 README.md）
└── LICENSE                     # Apache-2.0
```

> **布局纪律**：模块根只放元数据；库代码一律 `lib/`，实现细节 `lib/internal/`（**不要建 `src/`**）；
> 唯一例外是根空 `moon.pkg`（README 文档测试宿主）；测试放所属包内，
> `*_test.mbt`（黑盒）与 `*_wbtest.mbt`（白盒）**不可混用**。

---

## 工程约定与贡献

- **硬性约定（贡献前必读）**：[AGENTS.md](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/AGENTS.md)——密钥/Token 永不入库、
  不提交本地配置与构建产物、MoonBit 布局、文档死链零容忍、README 只保留结论+出处。
- **门禁**：`bash scripts/gates.sh`（一键全量；**未启用 push CI**，本地跑是唯一自动闸门）。
- **问题与建议**：提交至仓库 [Issue](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/issues)。
- **Git 钩子（可选）**：`git config core.hooksPath .githooks`（属个人本地配置，仓库不代设）。

---

## License

[Apache-2.0](LICENSE)
