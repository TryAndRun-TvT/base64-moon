#!/usr/bin/env bash
# docs-date-check.sh —— 状态头日期漂移**提示**（S12 §14 E2，仅警告不阻断）
#
# 目的：让状态头的 `日期` 名副其实——它应表达该篇**末次实质修订**的时间。
#   若 `日期` 明显早于末次实质 commit，说明该篇改过了但状态头没同步。
#
# 为什么只提示（不 exit 1）：
#   1. `git` 时间受 rebase / checkout / 提交时序影响，不是「文档真值」的强判据；
#   2. 「实质修订」的判定本身是启发式（下文口径），误判代价不该是红门禁。
#   故本脚本**永不返回非 0**（除文件系统级错误），输出仅为提醒。
#
# 「实质修订」口径（关键，两重过滤，都是为了压噪音）：
#   1. **滤掉只动状态头的 commit**：本仓库曾有批量补状态头的提交
#      （fb77d96，一次触摸 58 篇）——按「最后触摸」判定会让全库都「漂移」。
#      判据：该 commit 对该文件的改动行**全部**涉及 `状态`/`日期：`/`索引：`/空行 → 跳过。
#   2. **滤掉横切大批量 commit**（MAX_FILES，默认 3）：本仓库屡有「一改动半个 docs/」的
#      横切提交（后端收敛、批量改链、批量加状态头），它们不是**某篇自身**的修订。
#      判据：该 commit 改动的文件数 > MAX_FILES → 跳过。
#   3. **要求改动量达阈值**（MIN_LINES，默认 10）：只为「实质重写/新增章节」计时，
#      而非「一句交叉引用微调」。
#   实测：只加规则 1 时 58/58 篇全提示；加 2+3 后降到个位数 → 提示才有信噪比。
#
# 用法: bash scripts/docs-date-check.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "=== 状态头日期漂移提示（S12 §14 E2；仅警告）==="
python3 - <<'PYEOF'
import os, re, subprocess, sys

files = [f.decode() for f in subprocess.run(
    ["git", "ls-files", "-z", "docs/*.md"], capture_output=True).stdout.split(b"\0") if f]

HDR_ONLY = re.compile(r"状态|日期：|索引：|^[+-]\s*$")
MIN_LINES = int(os.environ.get("DOC_DATE_MIN_LINES", "10"))
MAX_FILES = int(os.environ.get("DOC_DATE_MAX_FILES", "3"))

def commits_of(path):
    out = subprocess.run(["git", "log", "--format=%H %ad", "--date=short", "--", path],
                         capture_output=True, text=True).stdout.strip()
    return [l.split() for l in out.split("\n") if l]

def touched_files(sha):
    out = subprocess.run(["git", "show", "--name-only", "--format=", sha],
                         capture_output=True, text=True).stdout
    return [l for l in out.split("\n") if l.strip()]

def is_substantial(sha, path):
    if len(touched_files(sha)) > MAX_FILES:
        return False          # 横切大批量 commit：不是本篇自身的修订
    d = subprocess.run(["git", "show", sha, "--format=", "--unified=0", "--", path],
                       capture_output=True, text=True).stdout
    changed = [l for l in d.split("\n")
               if l.startswith(("+", "-")) and not l.startswith(("+++", "---"))]
    return sum(1 for l in changed if not HDR_ONLY.search(l)) >= MIN_LINES

drift, unknown = [], []
for f in files:
    hdr_date = ""
    for line in open(f, encoding="utf-8"):
        if line.startswith("> **状态**："):
            m = re.search(r"日期：(\d{4}-\d{2}-\d{2})", line)
            hdr_date = m.group(1) if m else ""
            break
    if not hdr_date:
        unknown.append(f); continue
    last = None
    for sha, ad in commits_of(f):
        if is_substantial(sha, f):
            last = ad; break
    if last is None:
        unknown.append(f); continue
    if hdr_date < last:
        drift.append((f, hdr_date, last))

for f, h, c in drift:
    print("  ⚠️  %-58s 状态头 %s < 末次实质 commit %s" % (f, h, c))
print("  COUNT=%d（%d 篇无实质 commit 记录，已跳过）" % (len(drift), len(unknown)))
if drift:
    print("     提示：若该篇确已实质修订，请更新状态头 `日期：`；若只是元数据微调，可忽略。")
else:
    print("  ✅ 无日期漂移")
sys.exit(0)   # 仅提示，永不阻断
PYEOF
