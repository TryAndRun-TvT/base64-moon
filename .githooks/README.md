# Git Hooks

本目录存放可选的 Git 钩子，与 MoonBit 官方 `moon new` 生成的 `.githooks/` 保持一致。

## pre-commit

在提交前执行：

1. `moon fmt --check` —— 校验代码与配置格式（含 `moon.mod`、`moon.pkg`、所有 `.mbt`）
2. `moon check` —— 类型/告警检查

## 启用

```bash
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks
```

`core.hooksPath` 是**本地个人配置**，本仓库不代为设置，由开发者自行决定。

## 停用

```bash
git config --unset core.hooksPath
```

## 说明

- 未安装 `moon` 时钩子自动跳过（不阻断提交），便于非 MoonBit 环境的协作者。
- CI 中的等价校验见 `.cnb.yml`，钩子只是本地提前反馈，不是唯一防线。
