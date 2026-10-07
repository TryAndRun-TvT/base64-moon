#!/usr/bin/env bash
# docs-ref-check.sh —— 章节引用门禁（S12 §14 E1）
#
# 目的：`docs-link-check.sh` 只校验**文件级**链接可达，抓不到「篇章内部章节引用」
#   这类漂移。实证（S12 §13.4）：`S12 §3.3` 曾引用 **`S11 §9.1` / `S11 §9.2`**，
#   而 S11 的 §9 **没有子节**——整链门禁当时全绿，人工复核才发现。
#
# 两条判据（同一把尺子的两种写法）：
#   A. 代号式：文中形如 `S<N>[a-z] §M[.K...]` 的引用，必须在被引篇目内**存在该编号的标题**；
#   B. 路径式：文中形如 `[标签](路径.md) §M[.K...]` 的引用（链接紧跟 §），同样须存在该标题。
#      —— 补 B 的理由（2026-09-25 实证）：`wasm-编译与运行-结果分析.md §5.2` 这类**路径式**引用
#      在 A 下不可见（A 只认 `S<N>x` 代号），该篇被裁剪后留下 **18 处悬空 §** 而整链仍绿。
#   C. `已失效` 篇同样纳入扫描面（2026-09-30 加固，Issue #63）：
#      上述「18 处悬空 §」在 B 落地后**仍未清零**——因为被引篇目 `wasm-编译与运行-结果分析.md`
#      的状态是 `已失效`，而本脚本原按 `历史/现行` 判定「是否删篇」，把 `已失效` 当「已删」跳过。
#      这是**判据用错信号**：`已失效` 指「所述前提不成立、不得引用为口径」，**不等于文件不存在**；
#      文件仍在仓库内（可导航、可被 § 引用），故其章节引用与 `历史` 篇一视同仁地判定。
#   编号来源 = 被引篇目内形如 `## M` / `### M.K` 的标题前缀（两/三级标题并存都认）。
#
# 识别范围（保守，宁漏勿误）：
#   - 只认被引篇目在 `docs/` 里**存在**的 `S<N>[a-z]` 代号（映射见 maps）引用；
#     无法映射到具体文件的（如 `S9x` 泛指一族）**跳过**，不制造假红；
#   - 标题编号须以「数字开头 + 非数字结尾边界」匹配，避免 `§3` 匹配到 `§30`。
#
# 用法: bash scripts/docs-ref-check.sh
# 退出码: 0 = 无漂移；1 = 存在失效章节引用
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "=== 章节引用门禁（S12 §14 E1）==="
python3 - <<'PYEOF'
import os, re, subprocess, sys

SCAN_EXTRA = ["README.md", "AGENTS.md"]
# 判据 C：用 `git ls-files docs`（**整目录递归**）而非 `docs/*.md`——后者漏掉 `docs/*/*.md`
# 与 `docs/*/*/*.md`（D2 分类后全部文档都在子目录里），会让「被引篇目」集合凭空少一层。
files = [f.decode() for f in subprocess.run(
    ["git", "ls-files", "-z", "docs"], capture_output=True).stdout.split(b"\0")
    if f and f.decode().endswith(".md")]
for extra in SCAN_EXTRA:
    if os.path.isfile(extra):
        files.append(extra)

# 代号 → 文件：docs/ 内以 `S<N>[a-z]` 开头（可带 `-` 后缀）的 md
code2file = {}
for f in files:
    b = os.path.basename(f)
    m = re.match(r"^(S\d+[a-z]?)[-.]", b)
    if m:
        code2file.setdefault(m.group(1), []).append(f)

def headings(path):
    """返回该文件内所有标题编号集合（'3'、'3.2' 都收）。"""
    hs = set()
    for line in open(path, encoding="utf-8"):
        # 标题形如 `## 3. xxx` / `### 3.2 xxx`：取标题起始的编号（数字段 + 可选 `.数字` 段），
        # 编号后允许 `.`、空格、`、`等分隔符；用 (?![\d]) 防止 `3` 误配 `30`。
        m = re.match(r"^#{1,6}\s+(\d+(?:\.\d+)*)\.?(?![\d])", line.strip())
        if m:
            hs.add(m.group(1))
    return hs

cache = {}
def heads_of(path):
    if path not in cache:
        cache[path] = headings(path)
    return cache[path]

REF_RE = re.compile(r"\b(S\d+[a-z]?)\s*[§#]\s*(\d+(?:\.\d+)*)(?![\d])")

def strip_code_spans(line):
    """去掉行内 code span（反引号对）内容。

    反引号里的 `S11 §9.1` 是**对「失效引用」的引述**（如 S12 §13.4 记录曾修过的死引用），
    不是活引用；不剥离会制造假红。剥离后再匹配，才对应「读者能点/能跳」的引用。
    """
    return re.sub(r"`[^`]*`", "", line)

bad, scanned, skipped = [], 0, 0
for f in files:
    for lineno, line in enumerate(open(f, encoding="utf-8"), 1):
        for code, sec in REF_RE.findall(strip_code_spans(line)):
            targets = code2file.get(code)
            if not targets:
                skipped += 1
                continue
            scanned += 1
            if not any(sec in heads_of(t) for t in targets):
                bad.append((f, lineno, "`%s §%s`" % (code, sec), "/".join(targets)))

# ── B. 路径式引用：`[标签](X.md) §M` ──────────────────────────────────────────
# 只在「链接紧跟 §」的形态下判定（`§` 未必属于该链接，故用 **同一行 + 链接后紧邻** 收窄）。
LINK_SEC_RE = re.compile(r"\]\(([^)#]+\.md)\)\s*[§#]\s*(\d+(?:\.\d+)*)(?![\d])")

# 仓库内 `docs/` 子目录名（由 `git ls-files docs` 派生的实际目录集合）。
DOCS_SUBDIRS = sorted({
    f.split("/")[1] for f in files if f.startswith("docs/") and f.count("/") >= 2
})

def resolve(src, target):
    """把引用目标解析为仓库内真实路径。

    先按**相对引用方**解析（docs 内部互链的规范形态）；失败再试两种「仓库根相对」写法——
    (a) `docs/01-规格/X.md` 全路径；(b) `docs/X.md` 漏写子目录（D2 迁移后的高频笔误，
    如 `docs/S8-内部结构归位与分层.md` 实为 `docs/01-规格/S8-…md`）。
    这样「写错目录层级」也能被本门禁抓到，而不是被当成「目标不存在」静默跳过。
    """
    cands = [os.path.normpath(os.path.join(os.path.dirname(src), target))]
    cands.append(os.path.normpath(target))                      # (a) 仓库根相对
    if target.startswith("docs/") and target.count("/") == 1:    # (b) docs/X.md 补子目录
        base = target[len("docs/"):]
        for sub in DOCS_SUBDIRS:
            cands.append(os.path.normpath("docs/%s/%s" % (sub, base)))
    for p in cands:
        if os.path.isfile(p):
            return p
    return None

for f in files:
    for lineno, line in enumerate(open(f, encoding="utf-8"), 1):
        for target, sec in LINK_SEC_RE.findall(strip_code_spans(line)):
            tp = resolve(f, target)
            if not tp:
                continue          # 目标不存在由 docs-link-check 负责，此处不重复报
            if tp == f:
                continue          # 自指（同篇跨节）不判，避免同一篇内移动节次即红
            scanned += 1
            if sec not in heads_of(tp):
                bad.append((f, lineno, "`%s §%s`" % (target, sec), tp))

for f, lineno, what, where in bad:
    print("  ❌ %s:%d：引用 %s，但 %s 内无该编号标题" % (f, lineno, what, where))
print("  COUNT=%d" % len(bad))
print("  实扫 %d 处可映射引用；%d 处泛指代号已跳过" % (scanned, skipped))
sys.exit(1 if bad else 0)
PYEOF
