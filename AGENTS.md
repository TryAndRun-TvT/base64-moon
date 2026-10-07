# AGENTS.md — AI 协作代理仓库指南

> 本文件为在本仓库（MoonBit 项目 `base64-moon`）工作的 AI 编码代理提供硬性约定。
> 请优先遵守；违反可能导致密钥泄露或构建破坏。
> 本文件的配置来源与落地过程见
> [docs/03-过程/仓库初始化配置说明.md](./docs/03-过程/仓库初始化配置说明.md)。

---

## 一、Git 安全（最高优先级）—— 避免密钥 / 私人配置入库

1. **API Key / Token / Secret 永不写入任何入库文件**
   - 不得写入源码常量、配置文件、文档示例。
   - 本仓库当前为纯本地库项目；若将来接入需在 CI 中部署的服务，
     密钥一律走平台 Secret 注入，**不得**写入 `.cnb.yml` 的 `vars` 或任何跟踪文件。
2. **永不提交本地 Secret / 私人配置**
   - `.env*` / `.dev.vars*` / `.gitignore` 中声明的本地文件，**禁止** `git add -f` 强制添加。
   - 本地/私人配置保持未提交状态（`git status` 显示 `M` 属预期，**切勿 `git add`**）。
3. **不得入库构建产物**
   - `_build/`、`*.wasm`、`*.js`、`*.mbti` 均已 gitignore。
   - `moon info` 会生成 `*.mbti`，属构建产物，禁止提交。
4. **提交前自查**
   - `git status` + `git diff`：确认暂存区无 Secret、私人配置、构建产物混入。

---

## 二、MoonBit 项目约定

### 1. 包与文件放置

- **模块根只放元数据**（`moon.mod` / `README.md` / `docs/` 等）；库包统一放 `lib/`，
  实现细节藏 `lib/internal/`（**不要建 `src/`**）。
- **模块根唯一例外 = 空 `moon.pkg`**（README 文档测试宿主）：它是 README「示例即测试」落地的前提——
  `mbt check` 代码块由 `moon check` / `moon test` 当作文档测试运行，
  而模块根的 `.md` **只有归属到某个包才会被扫描**。
  该包**不含任何实现、不导出 API**（边界由 `lib/` 承担），已用 `warnings = "-29"`
  关掉「声明 `@lib` 但只在文档测试里使用」的 `unused_package` 告警。
  **不要把库代码放进根包。**
- 包按目录组织，每个目录一个 `moon.pkg`。
- 公共文件统一放 `lib/`，`.mbt` 文件名按职责命名；MoonBit 同包共享命名空间，
  **不设「入口注释文件」**。
- 测试文件放**所属包目录内**，分两类，**不可混用**：

  | 文件 | 运行位置 | 可访问范围 |
  |------|---------|-----------|
  | `*_test.mbt` | 包**外**（黑盒） | 仅 `pub` 导出的公共 API；用 `@lib` 别名引用本包（别名 = 目录名 `lib`，自动可用） |
  | `*_wbtest.mbt` | 包**内**（白盒） | 私有函数与内部实现，无需 `pub` 导出 |

- CLI 可执行包固定为 `cmd/main/`，其 `moon.pkg` 需写 `pkgtype(kind: "executable")`。
- 依赖方向无环：`lib` 可 import `lib/internal/*`，internal 永不反向 import `lib`（MoonBit 禁止 import 环）。

### 2. 依赖声明

- 跨包依赖在**使用方**的 `moon.pkg` 中声明：

  ```toml
  import {
    "TryAndRun-TvT/base64-moon/lib" @lib,
  }
  ```

- **声明后必须使用**：若声明了 `@lib` 却未实际使用，会触发 `unused_package` 告警
  并导致 `moon check` 失败。骨架阶段若无 API 可调用，**不要提前声明**。

### 3. 后端与构建

- 模块声明 `preferred_target = "wasm-gc"`，仅保留 `wasm-gc` 后端。
- 构建需显式指定包与后端：`moon build cmd/main --target wasm-gc --release`
  （模块根无包，构建需显式给包名）。
- **`native` 后端需系统 C 编译器**（`cc` / `gcc` / `clang`）。当前环境缺失，
  在修复前**不得**把 native 阶段写进门禁必选流程。
- 代码块以 `///|` 分隔块风格组织，块间顺序无关。

### 4. 收尾检查

每次改动后执行：

```bash
export PATH="$HOME/.moon/bin:$PATH"
moon fmt && moon info && moon check --deny-warn && moon test
# 后端回归（release，显式构建 lib 与 cmd/main）
moon build lib --target wasm-gc --release && moon build cmd/main --target wasm-gc --release
```

> **README 也是被测试的代码**：`README.md` 的 `mbt check` 代码块是**文档测试**
> （经 `README.mbt.md` 符号链接被扫描），`moon check` / `moon test` 会真编译、真运行。
> 改公共 API 而不同步改 README 示例 → **`moon test` 直接变红**。

> **push CI 未启用**（全量构建+测试对当前迭代节奏收益不成比例）。
> 门禁脚本均在 `scripts/` 下，改为本地/发布前按需执行：
>
> ```bash
> bash scripts/gates.sh                        # 一键全量门禁
> STAGES="check test" bash scripts/gates.sh    # 只跑指定阶段
> SKIP_SLOW=1        bash scripts/gates.sh     # 跳过 build-and-run
> ```
>
> 因此在推送前本地跑 `gates.sh`（或启用本地钩子）是**唯一**的自动质量闸门，不可省略。
> 可选启用本地钩子：`git config core.hooksPath .githooks`（属个人本地配置，仓库不代设）。

- `moon fmt` 会就地格式化（含 `moon.mod` / `moon.pkg`），提交前务必执行。
- `moon info` 生成的 `*.mbti` 是包的对外接口快照：若 `.mbti` 无变化，
  说明改动未影响对外可见接口，通常属安全重构。

---

## 三、测试约定

### 1. 三载体分工

| 载体 | 运行位置 | 可访问范围 | 用途 |
|------|---------|-----------|------|
| `*_test.mbt` | 包**外**（黑盒） | 仅 `pub` API | 锁公共契约 |
| `*_wbtest.mbt` | 包**内**（白盒） | 私有实现 | 锁实现细节 |
| 源码内联 `test {}` | 包内 | 私有 | 贴近实现的单行不变量 |

测试文件放**所属包目录内**；单测试文件 ≤800 行（`bash scripts/test-scale.sh` 校验），超长按主题拆分。

### 2. 测试铁律

1. **黄金值必须有出处**：参考值一律由 `scripts/` 下生成器产出，禁止手抄、禁止「跑一遍写下自己的输出」。
2. **黑盒锁契约、白盒锁实现**：公共 API 语义变化必须先体现在 `*_test.mbt`。
3. **禁止 `actual == actual`**：断言两端不得来自同一段实现逻辑。
4. **每个断言可定位**：失败信息须能指出函数 + 输入 + 参数。
5. **负向优先于正向**：先证明「测试能红」，再谈覆盖率。
6. **真值集合而非用例数**：评审看「独立真值点数 / 参数叉积」，拒绝机械展开的重复断言。
7. **测试不得有破坏性副作用**：不写临时文件、不改全局状态、不依赖执行顺序。

### 3. 例行检查

```bash
bash scripts/test.sh                  # moon test（黑盒 + 白盒）
bash scripts/test-scale.sh            # 单测试文件 ≤800 行护栏（进 gates）
bash scripts/docs-link-check.sh       # 文档互链死链检查（进 gates）
bash scripts/docs-ref-check.sh        # 章节引用门禁
bash scripts/docs-index.sh --verify   # 索引清单与实跑一致（生成物，勿手改）
bash scripts/docs-date-check.sh       # 状态头日期漂移**提示**（仅警告，永不阻断）
bash scripts/toolchain-probe.sh       # 工具链版本 + 全部告警 + 依赖图（只读/非阻断）
```

---

## 四、文档管理

- 文档统一放 `docs/`，命名用连字符分隔的小写词段（kebab-case，允许中英混排）。
- **单文档 ≤800 行**，超长应拆分。
- **死链零容忍**：文档中不得引用不存在的文件；新增文档须同步更新
  **两处索引**：`docs/README.md`（全量清单）与 `README.md` 的「文档索引」表。
  两处都须更新，否则 `bash scripts/docs-link-check.sh` 会红
  （`README.mbt.md` 是指向 `README.md` 的符号链接）。
- **README 正文改 `README.md`，不要改 `README.mbt.md`**：后者是符号链接。
  `README.md` 里的 `mbt check` 示例会被 `moon test` 校验，请勿把示例写回 `moonbit` 展示块。
- **不要在 README 里写会被写死的计数**（用例数 / 文件数 / 链接条数）：它们随实现漂移，
  写死必然自相矛盾。需要数字时指向实跑命令。
- **改公共 API 必须同步 README 示例**：否则 `moon test` 变红（文档测试即门禁）。
- **README 只保留「落地页 + 索引」**：只写「能做什么 / 怎么用 / 边界在哪 / 去哪看细节」——
  **结论 + 出处链接**。数字表、参数、实验设计、历史记录**一律下沉 `docs/`**。
- **README 里的跨文档链接：归档外目标一律用仓库绝对链接**：
  发布归档（`.moonignore`）**排除** `/docs/` 与 `/AGENTS.md`，故 README 中指向它们的**相对链接**
  会在 mooncakes 落地页被重写而 **404**。约定：`docs/**` / `AGENTS.md` →
  `https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/blob/main/<path>`；
  `README.md` / `LICENSE` / `cmd/main/**`（**在归档内**）→ 保留相对链接。
- **发布状态不写死具体版本号**：写「已发布（首个版本）」+ 指向 mooncakes 版本页。
- **纯本地 / 私人配置调整**：只改代码/配置，**不生成、不更新项目文档**。

### 4.1 文档准入（新增 / 修订文档前必过）

1. **头部三字段齐备**（缺一不予合入）：

   ```markdown
   > **状态**：现行 | 历史 | 已失效　｜　日期：YYYY-MM-DD　｜　索引：§N
   ```

   - `现行`：结论仍是对外口径，可直接引用；
   - `历史`：结论已并入某现行篇（**必须紧跟 `并入：[篇名]`**），本文仅留过程价值；
   - `已失效`：所述前提已不存在，**不得被引用为口径**。

2. **单文件 ≤800 行**；超出须拆出「承接篇」并在两处索引登记。
3. **可复跑原则**：任何**数字结论**必须附复跑命令，或指向登记处。
4. **不新建「索引的索引」**：导航层次 ≤2 级（`docs/README.md` → 分类 → 篇章）。
   `docs/**` 除索引自身外**不得**出现 `README.md`；域首页用「域-索引.md」命名。
5. **索引双更新**：`docs/README.md`（全量清单）+ `README.md` 的「文档索引」表。
6. **目录按读者意图分**：`01-规格/`（我要改代码）· `02-证据/`（我要审计数据）·
   `03-过程/`（我要复盘决策）· `04-元/`（我要改文档）。

---

## 五、参考

- 项目文档索引：[docs/README.md](docs/README.md)（**全量清单 + 按读者路径**）→
  [README.md](README.md)「文档索引」表（落地页入口；`README.mbt.md` 为其符号链接）。
- MoonBit 技能库：<https://github.com/moonbitlang/skills>
- MoonBit 构建系统：<https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/tutorial.html>
