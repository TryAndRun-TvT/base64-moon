#!/usr/bin/env bash
# docs-link-check.sh —— T6-c 文档互链死链检查（S10 §6 T6-c）
#
# 目的：把 AGENTS.md §四「死链零容忍」变成可执行门禁。
# 检查范围：仓库内**受版本控制**的 Markdown 文件（README.md / AGENTS.md / docs/**）
#          中的**相对链接**（`[text](path)` 与 `![alt](path)`）是否指向存在的文件/目录。
#
# 口径（重要）：
#   - 只检查**相对路径**：`http(s)://`、`mailto:`、`#anchor`（纯锚点）**跳过**
#     （外链可达性依赖网络，不适合进 CI；锚点校验需 Markdown 解析器，超出零依赖原则）。
#   - `path#anchor` 只校验 `path` 部分存在（锚点不校验）。
#   - 锚点内的 URL 编码（如 `%20`）会被解码后再判断。
#   - **忽略代码块**：``` 围栏内的示例链接不参与检查（避免把示例文本当死链）。
#   - **忽略行内 code span**：`...` 内的示例链接同样不参与检查（同上，示例非真链接）。
#
# 用法: bash scripts/docs-link-check.sh
#   LINK_CHECK_VERBOSE=1 bash scripts/docs-link-check.sh   # 打印每条链接
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "=== T6-c 文档互链死链检查 ==="
fail=0
checked=0

# 受版本控制的 Markdown（排除 _build / node_modules 等）
# 注：文件名含中文/空格，必须走 NUL 分隔读入，否则 awk 会拿到被转义的路径。
mapfile -d '' -t FILES < <(git ls-files -z '*.md' | grep -zvE '^(_build/|node_modules/)')
if (( ${#FILES[@]} == 0 )); then
  echo "!! 未找到受版本控制的 Markdown 文件" >&2
  exit 1
fi
echo "  扫描 ${#FILES[@]} 个 Markdown 文件"

for f in "${FILES[@]}"; do
  dir="$(dirname "$f")"
  # 提取相对链接目标；剔除代码块内容
  while IFS= read -r target; do
    [[ -z "$target" ]] && continue
    # 跳过外链/锚点/绝对路径
    case "$target" in
      http://*|https://*|mailto:*|tel:*|\#*|/*) continue ;;
    esac
    # 去锚点 + URL 解码
    path="${target%%#*}"
    [[ -z "$path" ]] && continue
    path="$(printf '%b' "${path//%/\\x}")"
    # 相对本文件所在目录解析
    resolved="$dir/$path"
    checked=$((checked + 1))
    if [[ "${LINK_CHECK_VERBOSE:-}" == "1" ]]; then
      printf '  · %s -> %s\n' "$f" "$target"
    fi
    if [[ ! -e "$resolved" ]]; then
      printf '  ❌ 死链：%s -> %s（解析为 %s，不存在）\n' "$f" "$target" "$resolved"
      fail=1
    fi
  done < <(awk '
    /^[[:space:]]*```/ { inblock = !inblock; next }
    inblock { next }
    { line = $0
      # 剔除**行内 code span**（`...`）：其中的 `[x](path)` 是文档举例，不是真链接。
      # 与上面「忽略 ``` 围栏」同源——示例文本不应被当作死链来源。
      while (match(line, /`[^`]*`/)) {
        line = substr(line, 1, RSTART - 1) " " substr(line, RSTART + RLENGTH)
      }
      while (match(line, /!?\[[^]]*\]\([^)]*\)/)) {
        seg = substr(line, RSTART, RLENGTH)
        sub(/^!?\[[^]]*\]\(/, "", seg)
        sub(/\)$/, "", seg)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", seg)
        # 去掉标题部分 [text](path "title")
        sub(/[[:space:]]+".*"$/, "", seg)
        print seg
        line = substr(line, RSTART + RLENGTH)
      }
    }' "$f")
done

echo "  已检查 $checked 条相对链接"
if (( fail )); then
  echo
  echo ">> 存在死链：请修正路径，或删除失效引用（AGENTS.md §四：死链零容忍）。"
  exit 1
fi
echo ">> 零死链。"
