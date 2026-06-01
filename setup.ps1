# Codex Computer Use 一键部署脚本
# 在目标电脑上以管理员身份运行此脚本
# PowerShell: .\setup.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Codex Computer Use 部署脚本" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ── 辅助函数 ──────────────────────────────────────────
function Copy-HashDir {
    param([string]$FileName, [string]$SourceBinDir, [string]$DestBinDir)
    $found = Get-ChildItem -Path $SourceBinDir -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName $FileName)
    }
    if (-not $found) {
        Write-Host "  [WARN] 找不到包含 $FileName 的哈希目录，跳过" -ForegroundColor Yellow
        return $false
    }
    $hashDir = $found[0]
    $destPath = Join-Path $DestBinDir $hashDir.Name
    if (Test-Path $destPath) {
        Write-Host "  [SKIP] $($hashDir.Name)\ 已存在" -ForegroundColor Gray
        return $true
    }
    Write-Host "  [COPY] $($hashDir.Name)\ ($FileName)" -ForegroundColor Green
    Copy-Item -Path $hashDir.FullName -Destination $destPath -Recurse
    return $true
}

# ── 步骤 1：检测 Codex 安装 ──────────────────────────
Write-Host "[1/4] 检测 Codex 安装..." -ForegroundColor White
$CodexBin = "$env:LOCALAPPDATA\OpenAI\Codex\bin"
if (-not (Test-Path $CodexBin)) {
    Write-Host "  [ERROR] 未找到 Codex 安装目录：$CodexBin" -ForegroundColor Red
    Write-Host "  请先安装 Codex 桌面版（Microsoft Store），然后重新运行此脚本。" -ForegroundColor Yellow
    exit 1
}
Write-Host "  [OK] 找到 Codex 安装" -ForegroundColor Green

# ── 步骤 2：复制运行时二进制文件 ──────────────────────
Write-Host "[2/4] 复制运行时二进制文件..." -ForegroundColor White
$DestBin = Join-Path $RepoRoot "bin"
New-Item -ItemType Directory -Force -Path $DestBin | Out-Null

$files = @("codex.exe", "node.exe", "node_repl.exe", "rg.exe")
$allOk = $true
foreach ($f in $files) {
    $result = Copy-HashDir -FileName $f -SourceBinDir $CodexBin -DestBinDir $DestBin
    if (-not $result) { $allOk = $false }
}

if (-not $allOk) {
    Write-Host "  [WARN] 部分二进制文件未能复制。如果目标 Codex 版本不同，" -ForegroundColor Yellow
    Write-Host "         哈希值会变化，请参考 README.md 重新计算。" -ForegroundColor Yellow
}

# ── 步骤 3：替换用户名占位符 ──────────────────────────
Write-Host "[3/4] 替换 config.toml 中的 <用户名> 占位符..." -ForegroundColor White
$ConfigPath = Join-Path $RepoRoot "config.toml"
if (Test-Path $ConfigPath) {
    $content = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
    if ($content -match "<用户名>") {
        $updated = $content -replace "<用户名>", $env:USERNAME
        [System.IO.File]::WriteAllText($ConfigPath, $updated, [System.Text.UTF8Encoding]::new($false))
        Write-Host "  [OK] 已替换为：$env:USERNAME" -ForegroundColor Green
    } else {
        Write-Host "  [OK] config.toml 中无占位符，已跳过" -ForegroundColor Gray
    }
}

# ── 步骤 4：检查 marketplace node_modules ─────────────
Write-Host "[4/4] 检查 marketplace 插件依赖..." -ForegroundColor White
$MarketplaceRoot = Join-Path $RepoRoot "marketplace\openai-bundled\plugins"
$BundledSrc = "$env:USERPROFILE\.codex\.tmp\bundled-marketplaces\openai-bundled\plugins"
if (Test-Path $BundledSrc) {
    $plugins = @("browser", "chrome", "computer-use")
    foreach ($p in $plugins) {
        $destNM = Join-Path $MarketplaceRoot "$p\scripts\node_modules"
        $srcNM = Join-Path $BundledSrc "$p\scripts\node_modules"
        if ((Test-Path $destNM) -or (-not (Test-Path $srcNM))) {
            Write-Host "  [SKIP] $p node_modules" -ForegroundColor Gray
            continue
        }
        Write-Host "  [COPY] $p node_modules (可能需要几秒...)" -ForegroundColor Green
        Copy-Item -Path $srcNM -Destination $destNM -Recurse
    }
} else {
    Write-Host "  [INFO] 未找到 Codex bundled marketplace，" -ForegroundColor DarkGray
    Write-Host "         node_modules 将在 Codex 首次启动后自动安装" -ForegroundColor DarkGray
}

# ── 完成 ──────────────────────────────────────────────
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " 部署完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "接下来的步骤：" -ForegroundColor White
Write-Host "  1. 将 config.toml 复制到 %USERPROFILE%\.codex\config.toml" -ForegroundColor Gray
Write-Host "  2. 将 computer-use\config.json 复制到 %USERPROFILE%\.codex\computer-use\config.json" -ForegroundColor Gray
Write-Host "  3. 将 marketplace\openai-bundled\ 复制到 %USERPROFILE%\.codex\.tmp\bundled-marketplaces\openai-bundled\" -ForegroundColor Gray
Write-Host "  4. 重启 Codex" -ForegroundColor Gray
Write-Host ""
Read-Host "按 Enter 退出"
