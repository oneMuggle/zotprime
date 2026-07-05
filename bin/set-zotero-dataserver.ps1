<#
.SYNOPSIS
    替换已安装 Zotero 5.0.96.3 客户端内的 dataserver URL (A' 构建期注入失败时的兜底)
.DESCRIPTION
    - 定位 Zotero 扩展 XPI（多路径候选）
    - 备份原 XPI
    - 用 System.IO.Compression 改 zip（PS 5.0+）
    - PS < 5.0 给出明确错误引导装 WMF 5.1
.PARAMETER InstallPath
    Zotero 安装路径，默认 $env:ProgramFiles\Zotero
.PARAMETER DataServerUrl
    dataserver URL（替换 https://api.zotero.org）
.PARAMETER StreamServerUrl
    stream server URL（替换 wss://stream.zotero.org）
.EXAMPLE
    .\set-zotero-dataserver.ps1 -DataServerUrl "http://zotprime.local:8080/" -StreamServerUrl "ws://zotprime.local:8081/"
#>
[CmdletBinding()]
param(
    [string]$InstallPath = "${env:ProgramFiles}\Zotero",
    [string]$DataServerUrl = "http://zotprime.local:8080/",
    [string]$StreamServerUrl = "ws://zotprime.local:8081/"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# PS 版本检查
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Warning "PowerShell $($PSVersionTable.PSVersion) detected (< 5.0)."
    Write-Warning "System.IO.Compression.FileSystem requires PS 5.0+."
    Write-Warning "Please install Windows Management Framework 5.1:"
    Write-Warning "  https://www.microsoft.com/en-us/download/details.aspx?id=54616"
    exit 3
}

# 1. 定位 XPI
$xpiCandidates = @(
    "$InstallPath\distribution\extensions\zotero@chnm.org.xpi",
    "$env:APPDATA\Zotero\Zotero\profiles\*\extensions\zotero@chnm.org.xpi"
)
$xpi = $xpiCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $xpi) {
    Write-Error "Zotero XPI not found. Searched:`n  $($xpiCandidates -join "`n  ")"
    exit 1
}
Write-Host "Found XPI: $xpi"

# 2. 备份
$bak = "$xpi.bak.$(Get-Date -Format yyyyMMddHHmmss)"
Copy-Item -Path $xpi -Destination $bak -Force
Write-Host "Backup: $bak"

# 3. 用 System.IO.Compression 改 zip
$tempDir = Join-Path $env:TEMP "zotero-xpi-$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir | Out-Null
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($xpi, $tempDir)

    # 4. 改 config.js
    $configJs = Join-Path $tempDir "resource\config.js"
    if (-not (Test-Path $configJs)) {
        throw "config.js not found at $configJs"
    }
    $content = [System.IO.File]::ReadAllText($configJs, [System.Text.Encoding]::UTF8)
    $content = $content -replace 'https://api\.zotero\.org', $DataServerUrl
    $content = $content -replace 'wss://stream\.zotero\.org', $StreamServerUrl
    [System.IO.File]::WriteAllText($configJs, $content, [System.Text.Encoding]::UTF8)
    Write-Host "Updated config.js: API_URL=$DataServerUrl, STREAM=$StreamServerUrl"

    # 5. 重打包
    Remove-Item -Path $xpi -Force
    [System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $xpi)
    Write-Host "Repacked XPI: $xpi"
}
finally {
    if (Test-Path $tempDir) {
        Remove-Item -Recurse -Path $tempDir -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Done. Restart Zotero to apply changes."
