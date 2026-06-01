# Codex Computer Use 插件修复过程

**日期**: 2026-06-01  
**环境**: Windows 11 Pro, Codex 26.527.3686.0 (Windows Store 安装)  
**问题**: Computer Use（电脑操控）插件显示"不可用"，`node_repl` 执行后端缺失，无法实际操控桌面

---

## 1. 问题诊断

### 现象
- Codex 设置中 Computer Use 插件显示"不可用"，无 Install 按钮
- 怀疑是灰度测试未覆盖

### 日志分析
查看 `D:\WpSystem\...\Logs\2026\06\01\` 下的日志，发现三个关键错误：

**错误 1**: `bundled_plugins_marketplace_resolve_failed`  
插件市场文件无法从 WindowsApps 解析。

**错误 2**: `bundled_executable_relocation_failed` (errno: -4094, syscall: "copyfile")  
codex.exe、node.exe、node_repl.exe、rg.exe 四个文件从 WindowsApps 复制到 `%LOCALAPPDATA%` 时全部失败。

**错误 3**: `browser_use_setup_failed backend=node_repl reason=node-repl-missing`  
node_repl 是 Computer Use 的 JS 执行后端，缺失导致电脑操控无法工作。

### 根本原因
Codex 作为 Windows Store 应用安装在受保护的 `WindowsApps` 目录中。Electron 的 `copyFileSync` 从该目录复制文件时因沙箱限制返回 errno -4094 (UNKNOWN)。Bash 命令行 `cp` 可以成功复制，但应用内 `fs.copyFileSync` 无法完成。

---

## 2. 修复步骤

### 步骤一：修改 config.toml

**文件**: `C:\Users\<用户名>\.codex\config.toml`

添加/修改以下配置：

```toml
# 启用电脑操控功能开关
[features]
computer_use = true

# 将沙箱从 "elevated" 改为 "unelevated"（解决 os error 740）
[windows]
sandbox = "unelevated"
```

`sandbox = "unelevated"` 修复了 `codex-windows-sandbox-setup.exe` 因请求管理员权限而报 os error 740 的问题。

---

### 步骤二：手动复制插件市场文件

Codex 需要将插件从 WindowsApps 复制到用户目录，但 `copyFileSync` 失败。手动执行：

```
源: C:\Program Files\WindowsApps\OpenAI.Codex_26.527.3686.0_x64__2p2nqsd0c76g0\app\resources\plugins\openai-bundled
    ↓
目标: C:\Users\<用户名>\.codex\.tmp\bundled-marketplaces\openai-bundled
```

然后在 config.toml 注册市场和插件：

```toml
[marketplaces.openai-bundled]
last_updated = "2026-06-01T00:00:00Z"
source_type = "local"
source = "\\\\?\\C:\\Users\\<用户名>\\.codex\\.tmp\\bundled-marketplaces\\openai-bundled"

[plugins."computer-use@openai-bundled"]
enabled = true

[plugins."browser@openai-bundled"]
enabled = true
```

**结果**: Computer Use 插件在 Codex UI 中显示为"已安装、已启用"，原生管道 (`codex-computer-use.exe`) 也成功启动。

---

### 步骤三：手动复制运行时二进制文件

将 6 个文件从 WindowsApps 复制到 `%LOCALAPPDATA%\OpenAI\Codex\bin\`：

```
codex.exe                        (253 MB)
node.exe                         ( 91 MB)
node_repl.exe                    ( 13.5 MB)
codex-windows-sandbox-setup.exe  (  8.3 MB)
codex-command-runner.exe         (  1.2 MB)
rg.exe                           (  4.2 MB)
```

**结果**: 文件已就位，但 node_repl 仍报 "missing"。因为应用期望文件在 **哈希子目录** 中，而非直接在 bin 目录下。

---

### 步骤四：核心修复 — 创建哈希子目录

#### 原理
通过分析 `app.asar` 中的重定位代码（函数 `Mc`、`Bc`、`Uc`、`Hc`），发现 Codex 不是直接使用 `bin/node_repl.exe`，而是将其放在按内容哈希命名的子目录中。

**哈希计算逻辑**（从 `Hc` 函数提取）:
```
SHA256("可执行文件名" + "\0" + "文件内容SHA256" + "\0" + ...)
取前 16 位十六进制 = 子目录名
```

如果目标哈希目录中文件已存在且内容哈希匹配（`Uc` 函数检查），则跳过 WindowsApps 复制，直接返回路径。

#### 计算过程
```bash
# 先计算每个文件的 SHA256
sha256sum codex.exe     → db991d1d96ee2f3f...
sha256sum node.exe      → 63c259c81e5d472b...
sha256sum node_repl.exe → cd5855513159366c...
sha256sum rg.exe        → decdd4992f3f1b9a...

# 再计算组合哈希（名字+内容摘要）
# node_repl.exe 无兄弟文件，组合输入为：
printf 'node_repl.exe\0cd5855513159366c...\0' | sha256sum
→ 34ab3e1324cc55b53ea0e6f218d440c6a9380827e092352d19b1b11b5efebb4f
→ 子目录名: 34ab3e1324cc55b5
```

#### 创建的目录结构

```
%LOCALAPPDATA%\OpenAI\Codex\bin\
├── 7dea4a003bc76627\
│   ├── codex.exe
│   ├── codex-windows-sandbox-setup.exe
│   └── codex-command-runner.exe
├── 5b9024f90663758b\
│   └── node.exe
├── 34ab3e1324cc55b5\
│   └── node_repl.exe
├── ada252862d154cdd\
│   └── rg.exe
├── codex.exe                      ← 原始直接复制（备份用）
├── node.exe
├── node_repl.exe
├── rg.exe
├── codex-windows-sandbox-setup.exe
└── codex-command-runner.exe
```

**结果**: Codex 启动时 `Uc()` 检查哈希目录，发现文件存在且哈希正确，跳过 WindowsApps 复制，`node_repl` 成功暴露。Computer Use 可以正常调用 JS 执行工具。

---

### 步骤五：app.asar 补丁（可选增强）

#### 修改内容
文件: `.vite/build/src-DJzHq3CP.js` (从 app.asar 提取)

在 `Mc()` 函数中添加回退逻辑：

```javascript
// 修改前
if(n===`win32`&&Jc(o)&&i!=null)try{return Bc(...)}

// 修改后
if(n===`win32`&&Jc(o)&&i!=null)try{if(el(i))return i;return Bc(...)}
```

作用：当目标文件已存在时（即使不在哈希目录中），直接使用，不再尝试从 WindowsApps 复制。

#### 打包命令
```bash
npx @electron/asar pack app-extracted app-patched.asar
```

#### 状态
补丁 asar 已生成（`C:\Users\<用户名>\.codex\.tmp\app-patched.asar`），但因 WindowsApps 目录受 TrustedInstaller 保护，需管理员权限才能替换。**仅哈希目录修复已足够解决问题，此步骤可选。**

---

## 3. 涉及的关键文件

| 文件 | 路径 |
|------|------|
| 配置文件 | `C:\Users\<用户名>\.codex\config.toml` |
| 二进制目录 | `%LOCALAPPDATA%\OpenAI\Codex\bin\` |
| 插件市场副本 | `C:\Users\<用户名>\.codex\.tmp\bundled-marketplaces\openai-bundled\` |
| app.asar 备份 | `C:\Users\<用户名>\.codex\.tmp\app.asar.backup` |
| 补丁 app.asar | `C:\Users\<用户名>\.codex\.tmp\app-patched.asar` |
| Computer Use 配置 | `C:\Users\<用户名>\.codex\computer-use\config.json` |

---

## 4. 维护说明

**Codex 版本更新时**：
- 需重新计算各可执行文件的 SHA256 和组合哈希
- 创建新的哈希子目录并复制新版本二进制文件
- 检查 config.toml 中 marketplace 的 `source` 路径是否需要更新

**Computer Use 再次不可用时**：
1. 检查 `%LOCALAPPDATA%\OpenAI\Codex\bin\` 下是否有新的哈希前缀目录
2. 确保新目录中包含对应版本的 exe 文件
3. 检查 config.toml 中 `sandbox` 为 `unelevated`、`computer_use` 为 `true`
