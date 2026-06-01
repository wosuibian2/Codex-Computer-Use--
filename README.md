# Codex Computer Use 一键部署包

在另一台电脑上开箱启用 Codex Computer Use 插件。

## 适用条件

- Windows 10/11
- Codex 桌面版 **26.527.3686.0**（Windows Store 安装）
- 如果目标电脑 Codex 版本不同，哈希值会变化，需要重新计算（见"版本不匹配"章节）

## 目标电脑上需要还原的文件

### 0. 运行一键部署脚本

**首先运行 `setup.ps1`**（以管理员身份打开 PowerShell）：

```powershell
.\setup.ps1
```

脚本会自动完成：
- 从本地 Codex 安装目录复制 `bin/` 运行时文件
- 替换 `config.toml` 中的 `<用户名>` 占位符
- 复制 marketplace 插件所需的 `node_modules`

### 1. 复制 config.toml 和插件配置

```
复制 → C:\Users\<你的用户名>\.codex\

config.toml                       → C:\Users\<用户名>\.codex\config.toml
computer-use\config.json          → C:\Users\<用户名>\.codex\computer-use\config.json
```

### 2. 复制插件市场文件

```
marketplace\openai-bundled\  →  C:\Users\<用户名>\.codex\.tmp\bundled-marketplaces\openai-bundled\
```

### 3. 重启 Codex

关闭并重新打开 Codex，检查 Computer Use 插件是否可用。

---

## 版本不匹配时如何重新计算哈希

如果目标电脑 Codex 版本不同：

1. 找到目标电脑 Codex 安装目录（`WindowsApps\OpenAI.Codex_xxx\app\resources\`）中的 exe 文件
2. 计算每个文件的 SHA256
3. 计算组合哈希（目录名）：

```bash
# 以 node_repl.exe 为例（无兄弟文件）
DIGEST=$(sha256sum node_repl.exe | cut -d' ' -f1)
printf 'node_repl.exe\0%s\0' "$DIGEST" | sha256sum
# 取前 16 位作为目录名
```

4. 创建对应的哈希目录并复制文件

**codex.exe 需要两个兄弟文件一起参与哈希计算**：`codex-windows-sandbox-setup.exe` 和 `codex-command-runner.exe`。

---

## 文件说明

| 文件 | 说明 |
|------|------|
| `setup.ps1` | 一键部署脚本（自动获取 bin/ 文件并替换用户名占位符） |
| `config.toml` | 主配置（已脱敏，占位符为 `<用户名>`） |
| `computer-use/config.json` | Computer Use 界面配置 |
| `marketplace/openai-bundled/` | 插件市场文件（node_modules 除外，由 setup.ps1 从本地 Codex 安装复制） |
| `修复过程.md` | 详细的修复过程和技术分析 |

**注意**：`bin/` 目录不再包含在仓库中。`setup.ps1` 会自动从本地 Codex 安装目录（`%LOCALAPPDATA%\OpenAI\Codex\bin\`）复制所需文件。哈希目录名会随 Codex 版本变化。

---

## 已移除的文件及说明

以下文件因体积过大或可公开获取，未包含在仓库中（`setup.ps1` 自动处理带 `[auto]` 标记的项）：

| 文件 | 用途 | 如何获取 |
|------|------|----------|
| `bin/` (356MB) | 运行时二进制文件：codex.exe, node.exe, node_repl.exe, rg.exe | `[auto]` `setup.ps1` 从 `%LOCALAPPDATA%\OpenAI\Codex\bin\` 自动复制 |
| `marketplace/**/node_modules/` (16MB) | 插件 npm 依赖 | `[auto]` `setup.ps1` 从本地 Codex bundled marketplace 自动复制；也可在 Codex 首次启动后自动安装 |
| `app.asar.backup` | 原始 app.asar 备份（138MB） | 从目标电脑 `WindowsApps\OpenAI.Codex_xxx\app\resources\app.asar` 自行备份 |
| `app-patched.asar` | 打过补丁的 app.asar（147MB） | 正常情况**不需要**，哈希目录修复已足够。如需生成：用 `npx @electron/asar extract` 解包原 asar，修改 `.vite/build/src-DJzHq3CP.js` 中 `Mc()` 函数添加 `if(el(i))return i;` 回退检查，再用 `npx @electron/asar pack` 打包。详见过 `修复过程.md` 步骤五 |
| `codex-global-state.json` | Codex 全局状态 | 包含聊天记录和个人信息，**已删除**。目标电脑上 Codex 会自动生成 |
| `src-DJzHq3CP-patched.js` | JS 补丁源码 | 如需要可从 `修复过程.md` 步骤五了解修改内容 |

### app.asar 补丁说明

哈希目录修复（步骤 3）**已足够**让 Computer Use 工作。asar 补丁是可选增强：当目标文件已存在于 bin 目录时，跳过从 WindowsApps 的复制操作。只有在哈希目录方案因某种原因失效时才需要。部署需要管理员权限替换 WindowsApps 下的受保护文件。
