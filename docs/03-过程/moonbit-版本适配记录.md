# MoonBit 版本适配记录（工具链漂移 → 适配裁决）

> **状态**：现行　｜　日期：2026-10-13　｜　索引：[docs/README.md](../README.md) §0

> 一句话结论：**这次升级看着吓人（`Int` 变了、命名参数符号变了、多出三类告警），
> 实测全是「源码写法的归一化」——公开接口快照逐字节不变，语义零变化。**
> 需要动的只有三件事：接受 `moon fmt` 的新排布、把期望版本升到 `0.1.20261012`、
> 把「默认关闭的潜伏告警」登记在案（**不开**）。`lib/` 的**逻辑**一行未改。

## 0. 本文回答什么

| 问题 | 答案 | 落在哪 |
|------|------|--------|
| 新工具链到底改了什么？ | 三类：类型名归一、命名参数符号归一、新增默认关闭告警 | §2 |
| 有没有破坏兼容性？ | **没有**。`Int` ≡ `Int32`，`x=` 调用式全兼容，`.mbti` 逐字节不变 | §3 |
| 要改哪些代码？ | 8 个文件被 `moon fmt` 重排（纯换名），**逻辑零改动** | §4 |
| 要不要关掉新告警？ | **不要**。全部是默认关闭的 opt-in 告警，`--deny-warn` 仍绿 | §5 |
| 怎么防以后再被咬？ | 版本期望升位 + 记录归档 + `toolchain-probe.sh` 常备 | §6 |

**触发**：ISSUE #29「适配 moonbit 版本更新」，
线索来自 [#27 的评审评论](https://cnb.cool/tryandrun/moonbit_dev/base64-moon/-/issues/27#comment-2109649561273311232)——
上一轮 PR #28 已**观察到**漂移并选择「不顺带重排源码」，本文是那笔账的**结清**。

---

## 1. 议题：什么变了、怎么发现的

上一轮（PR #28）在 `0.1.20261012` 上跑门禁，**只有 `fmt-check` 一处红**，
其余七道全绿。评论当时的判断是：

> 新工具链会把 `Int` 规范化成 `Int32`、`alphabet?` 规范化成 `alphabet~`，
> 导致 `fmt-check` 在既存 `.mbt` 文件上红。要不要把期望版本升上去 / 接受新格式，是独立一件事。

ISSUE #29 就是把这件事**独立办掉**：查清影响面、给裁决、落文档。

---

## 2. 变化清单（实测，不靠文档转述）

复跑：`bash scripts/toolchain-probe.sh`（只读、非阻断）。

### 2.1 类型名归一：`Int` → `Int32`

**实测证据**（探针原文见 §4.2）：`let x : Int = 1; let y : Int32 = 1; assert_eq(x, y)`
**编译通过**。更严的一版：把 `(Int) -> Int` 的函数赋给 `(Int32) -> Int32` 的变量、
两类型直接相加，**全部通过**。

=> **`Int` 是 `Int32` 的别名，不是独立类型。** 这是一次**改名**，不是一次**类型变更**。

### 2.2 命名参数符号：声明 `x?` → 声明 `x~`

- **声明侧**：`pub fn encode(data, alphabet? : Alphabet = Standard)`
  → `moon fmt` 重排为 `alphabet~ : Alphabet = Standard`。
- **调用侧**：`moon fmt` **只**把「裸标识符值」的 `key=value` 折成 `key~`：
  - `encode(x, padding=padding)` → `encode(x, padding~)` ✅ 会改
  - `encode(x, padding=false)` → 不变（值不是标识符）✅ 不改
  - `encode(x, alphabet=@lib.Alphabet::url_safe())` → 不变（值是构造调用）✅ 不改

=> `key~` 是**标签省略（label punning）**，等价于 `key=key`；
它**不是**新的传值语法（`key~value` 是语法错误，实测 §4.2）。

### 2.3 新增默认关闭告警（`--warn-list +a` 可见）

| 告警 | 含义 | 本仓命中数（`+a` 口径） |
|------|------|------|
| `unnecessary_view_op`（0075） | 期望类型已是视图，`[:]` 冗余 | 165（lib 110 / internal 52 / cmd 3） |
| `missing_invariant`（0038） | 证明受检 `for` 循环缺 `proof_invariant` | 28 |
| `missing_reasoning`（0039） | 同上，缺 `proof_reasoning` | 28 |
| `result_error_return` | `Result` 错误返回路径提示 | 14 |
| `unnecessary_annotation` | 冗余类型标注 | 3 |

对应新能力：`moon prove`（证明检查，见 `moon help` 的 `prove` 子命令）。

---

## 3. 兼容性裁决：零 API 影响

### 3.1 最强证据：`.mbti` 接口快照逐字节不变

`.mbti` 是 `moon info` 产出的**对外可见接口快照**。适配前后分别生成并对比：

```
diff /tmp/old.mbti /tmp/new.mbti          # lib
diff /tmp/old-internal.mbti /tmp/new-internal.mbti   # lib/internal
```

**两者均 IDENTICAL。** 两个反直觉但关键的点：

- 快照里参数仍写作 `alphabet?`（**不是** `alphabet~`）——`~` 只是**源码排布约定**，
  `.mbti` 把它归一化回 `?`；
- 快照里 32 位整数仍写作 `Int`（**不是** `Int32`）——别名在接口层被归一化回 `Int`。

=> 对任何下游消费者，**这次升级的可见面是空的**。

### 3.2 调用方兼容矩阵（实测）

| 调用写法 | 升级前 | 升级后 | 结论 |
|---------|:---:|:---:|------|
| `f(x, key=identifier)` | ✅ | ✅（fmt 折成 `key~`） | 兼容 |
| `f(x, key=literal_or_ctor)` | ✅ | ✅（fmt 不动） | 兼容 |
| `f(x, key~)`（punning） | — | ✅（新写法） | 新增能力 |
| `f(x, key~value)` | — | ❌ 语法错误 | 从未合法 |

### 3.3 因此：升级是「安全的」

- 运行期行为：43 例测试全绿，CLI 实跑输出一致；
- 接口契约：`.mbti` 不变；
- 调用侧：现有 `key=` 写法**无需改动**。

---

## 4. 适配方案与落地

### 4.1 方案：接受新排布，不手工改、不逐行审

裁决是「**接受**」而非「抵抗（钉在旧版）」或「手工挑改」。三条理由：

1. **抵抗不成立**：官方只提供 `latest` / `nightly` 通道，**指定版本号下载 404**（见
   `scripts/setup-moonbit.sh` 的「版本可复现性」段），钉死旧版做不到。
2. **改法必须是 `moon fmt` 而不是手改**：手改必然与格式器再打架，下一轮 `fmt-check` 又红。
   `moon fmt` 一次通过后 `moon fmt --check` **幂等**（实测连跑两次 EXIT=0）。
3. **风险为零**：§3 已证 `.mbti` 不变，故「接受新排布」不承担语义风险。

### 4.2 落地动作

| 动作 | 命令 / 位置 | 结果 |
|------|------------|------|
| 重排源码 | `moon fmt` | 8 文件、41 行变化，**全是类型名/参数符号** |
| 升期望版本 | `scripts/setup-moonbit.sh` 的 `MOON_EXPECTED_VERSION` | `0.1.20260920` → `0.1.20261012` |
| 记录变更 | 同上脚本的「版本变更记录」注释块 | 单一出处，升位时追加一行 |
| 探针清理 | 探针文件跑完即删、不入库 | 遵守 S6/S10 既有纪律 |

**受影响文件**（全部为 `moon fmt` 自动产出，无手改）：

```
lib/base64_matrix_test.mbt   签名 Int → Int32
lib/facade.mbt               4 个 pub fn 的 Int → Int32 + 命名参数 ~ + 转调
lib/internal/decode.mbt      6 处 Int/UInt → Int32/UInt32
lib/internal/encode.mbt      2 处返回值 Int → Int32
lib/internal/engine.mbt      decode_table : FixedArray[Int] → [Int32]
lib/internal/error.mbt       错误载荷 Int → Int32
lib/internal/pad.mbt         written/返回 Int → Int32
lib/internal/tables.mbt      build_decode_table 返回 Int32
```

复跑：`bash scripts/gates.sh`（八阶段，适配后全绿）。

### 4.3 探针源码（本次实测用，跑完已删）

留档以便复现两个最关键的「兼容性」断言：

```bash
# 探针 A：Int ≡ Int32（编译通过 ⇒ 别名）
cat > lib/probe_test.mbt <<'EOF'
///|
fn takes_int(x : Int) -> Int { x + 1 }
///|
fn takes_int32(x : Int32) -> Int32 { x + 1 }
///|
test "probe" {
  let a : Int = 1
  let b : Int32 = 2
  assert_eq(a + b, 3)
  let f : (Int) -> Int = takes_int32    // 互为别名才允许
  assert_eq(f(1), 2)
}
EOF

# 探针 B：key~ 是 punning，不是传值语法
#   f(x, key~)          ✅
#   f(x, key~value)     ❌ Parse error
```

---

## 5. 告警裁决：全部「登记不开」

### 5.1 关键前提：这些告警**默认关闭**

实测：`moon check`（不带 `--warn-list`）在**强制重检**后仍**零告警**，
`scripts/check.sh`（`moon check --deny-warn`）保持绿。所有上表数字都只在 `--warn-list +a` 下出现。

=> 「命中 165 个告警」**不等于**「仓库有 165 个问题」——
它们是**可选的诊断视图**，不是门禁项。

### 5.2 逐条裁决

| 告警 | 要不要开 | 理由 |
|------|:---:|------|
| `unnecessary_view_op` | **择机** | 165 处 `[:]` 冗余，属风格债；但**改了要走复跑**，且收益为零。登记待办，不塞进本次 |
| `missing_invariant` / `missing_reasoning` | **不开** | 绑定 `moon prove` 的形式化证明流程；本仓未做证明检查，强行满足会往热路径塞 `where` 子句 |
| `result_error_return` | **不开** | 是提示而非缺陷；本仓 `Result` 用法经 S5/S9 裁决，非本次变更引入 |
| `unnecessary_annotation` | **不开** | 3 处，收益低于噪声 |

### 5.3 为什么不「顺手清零」

- `unnecessary_view_op` 的 165 处多在**内循环附近的切片**上；
  虽属语法层冗余，但按 AGENTS.md §三「测试铁律」与 S9/S10 的纪律，
  **任何触及内循环的改动都要带复跑证据**——本次是「适配」，不该夹带性能实验。
- 强行开 `--deny-warn` 收窄告警集，会把「工具链默认视图」变成「本仓特例」，
  反而增加下次升级的摩擦。**保持默认，债登记在案。**

---

## 6. 防复发

| 措施 | 位置 |
|------|------|
| 期望版本与变更记录单一出处 | `scripts/setup-moonbit.sh`（`toolchain-probe.sh` 反查该文件） |
| 潜伏告警常备探针 | `bash scripts/toolchain-probe.sh`（只读、非阻断，永不让告警砸红） |
| 提交前全量门禁 | `bash scripts/gates.sh`（八阶段，本次全绿） |
| 版本漂移的已知代价 | 见 [E1 §2.3 / §10.6](../02-证据/E1-外部对照基线与分向根因.md)——**绝对值不可跨轮引用** |

---

## 7. 边界（本文不主张什么）

1. **本文不含性能结论**。`Int`→`Int32` 是改名、非类型变更，故**不影响** S6–S11 任何数字；
   但 E1 已记录「工具链漂移会静默改变被测量」，故跨轮绝对值仍不可比。
2. **本文不改 `lib/` 逻辑**。8 个文件的改动全部由 `moon fmt` 产出，可用 `fmt-check` 复核。
3. **`unnecessary_view_op` 的 165 处未清理**，属登记的后续可选事项，本仓当前**不主张**其形态有问题。
4. **未启用 `moon prove`**。`missing_invariant` / `missing_reasoning` 仅登记，不代表本仓承诺形式化证明。

---

## 8. 复跑命令

```bash
export PATH="$HOME/.moon/bin:$PATH"
bash scripts/toolchain-probe.sh        # ① 版本 + ② 潜伏告警 + ③ 依赖图
bash scripts/gates.sh                  # 全量八阶段门禁（应全绿）
bash scripts/fmt-check.sh              # 单跑格式门禁
moon fmt --check                       # 幂等性：连跑两次都应 EXIT=0
```
