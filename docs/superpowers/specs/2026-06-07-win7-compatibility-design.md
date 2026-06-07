---
title: ZotPrime Win7 兼容性方案设计稿
status: Draft（待用户审核）
date: 2026-06-07
branch: feature/win7-compatibility
author: brainstorming-session
related:
  - README.md
  - docs/intranet-deployment.md
  - docs/intranet-package-guide.md
---

# ZotPrime Win7 兼容性方案设计稿

## 1. 背景与目标

ZotPrime2 是自托管 Zotero 平台，由 dataserver（PHP）+ 多个 Docker 服务（mariadb、redis、minio、stream-server 等）+ Zotero 桌面客户端三部分组成。

内网部署场景中，部分用户机器仍运行 Windows 7 SP1。当前 zotprime 提供的 Zotero 桌面客户端（基于 Zotero 6 时代 Gecko 60.9.0esr 构建链 + Zotero 8.0.1 客户端源码）未对 Win7 兼容性做明确声明，且 Zotero 5 之后官方已逐步收紧 Win7 支持。NSIS 安装器残留 `MinSupportedVer "Microsoft Windows XP SP2"` 文本与底层 Gecko 60 ESR 真实最低系统要求（Win7 SP1）不一致，存在误导。

**目标：**

- 让内网 Win7 SP1 用户能够安装并使用 Zotero 桌面客户端，连接 ZotPrime dataserver 完成文献同步
- 不破坏现有 Win10/Win11 用户的客户端分发链路
- 在新分支 `feature/win7-compatibility` 下实施，develop 不受污染

**非目标：**

- 不为 dataserver、bin/ 管理脚本、stack/ 容器服务增加 Win7 兼容性代码（这些运行在 Linux 服务器，与 Win7 无关）
- 不在 8.0 源码上加 Win7 补丁（高风险、低收益，已通过调研否决）
- 不支持 32 位 Win7（内网用户群默认 64 位）
- 不支持 Windows XP / Vista / Server 2008（不在 Gecko 60 ESR 官方支持窗口内）

## 2. 方案选型

经调研与三方案对比，选用**方案 C：双版本并行**：

| 方案 | 简述 | 取舍 |
|------|------|------|
| A 锁回 5.0.96.3 | 所有用户都用 5.0.96.3 | 功能集是 2020 年的，缺内置 PDF 阅读器 |
| B 8.0 + Win7 补丁 | 保留 8.0，加 Win7 兼容 | Zotero 8 源码 + Gecko 60 ESR 兼容性未官方背书，有运行时崩溃风险 |
| **C 双版本并行**（已选） | Win7→5.0.96.3，Win10+→8.0+ | 维护成本 ×2，但用户体验完整 |

## 3. 架构概览

### 3.1 目录结构

```
zotprime (分支: feature/win7-compatibility)
├── client/
│   ├── zotero-standalone-build      # 现代版构建 (Gecko 60.9.0esr, 6.0.37-1)
│   ├── zotero-standalone-build-win7 # ★ 新增：Win7 专用 (5.0.96.3 tag)
│   ├── zotero-client                # 现代版源码 (8.0.1.SOURCE)
│   ├── zotero-client-win7           # ★ 新增：5.0.96.3 同期源码
│   └── zotero-build                 # XPI/翻译包（共享）
├── prebuild_client.Dockerfile       # 现代版 Linux tarball
├── prebuild_client_win7.Dockerfile  # ★ 新增：5.0.96 系列 tarball
├── clientbuildtest.Dockerfile       # 现代版构建测试
├── clientbuildtest_win7.Dockerfile  # ★ 新增：5.0.96 构建测试
├── bin/
│   ├── build-local.sh               # 改：增加 WIN7=1 开关
│   ├── detect-win-version.sh        # ★ 新增：探测 Windows 版本
│   ├── install.sh                   # 不改
│   ├── deploy-intranet.sh           # 改：按 OS 分发安装包
│   └── package-for-intranet.sh      # 改：打包两个客户端产物
├── docs/
│   ├── superpowers/specs/
│   │   └── 2026-06-07-win7-compatibility-design.md  # 本文档
│   ├── technical/
│   │   └── 18-win7-compatibility.md # ★ 新增章节
│   └── user-manual/
│       └── 09-win7-installation.md  # ★ 新增章节
└── tests/                            # ★ 新增目录
    ├── bin/
    │   ├── detect-win-version.bats
    │   └── build-local.bats
    ├── integration/
    │   └── win7-build.bats
    └── submodule/
        └── win7-refs.bats
```

### 3.2 数据流（构建 → 打包 → 部署 → 运行）

```
开发机 / CI
  │
  │ ① git submodule add + set-branch --branch 5.0.96.3
  ▼
client/zotero-standalone-build-win7  @ 5.0.96.3
client/zotero-client-win7            @ 5.0.96.3 同期 commit
  │
  │ ② WIN7=1 bin/build-local.sh
  ▼
Docker 构建 (prebuild_client_win7.Dockerfile)
  │   基础镜像: zotprime-build-base (复用)
  │   步骤: fetch_xulrunner → 编译 Gecko 60 → NSIS 打包
  ▼
产物: dist/Zotero-5.0.96.3_win-x86_64-setup.exe
       dist/Zotero-5.0.96.3_win-x86_64-setup.exe.sha256
  │
  │ ③ bin/package-for-intranet.sh (同时收 Win10+ 与 Win7 包)
  ▼
内网部署包/
  ├── clients/
  │   ├── win10plus/   (Zotero-8.0.1_...-setup.exe + .sha256)
  │   └── win7/        (Zotero-5.0.96.3_...-setup.exe + .sha256)
  ├── clients-manifest.json  # 新增
  ├── bin/deploy-intranet.sh (按 OS 分发)
  └── ... (其余 13 个 Docker 镜像，不变)
  │
  │ ④ 部署时: deploy-intranet.sh 调用 detect-win-version.sh
  ▼
  探测结果: win7/win8 → 拷贝 clients/win7/ 的安装包
            win10/win11 → 拷贝 clients/win10plus/ 的安装包
            unknown → 默认 win10plus + 人工跟进
  │
  │ ⑤ Win7 用户双击 Zotero-5.0.96.3_...-setup.exe
  ▼
  NSIS 安装 (走 AtLeastWin7 分支，装到 Program Files)
  启动 → 连 ZotPrime dataserver (http://<SERVER_IP>:8080/)
  同步 → Zotero 5.0 协议（与 dataserver 6.0/7.0 兼容）
```

## 4. 组件分解

| # | 组件 | 路径 | 职责 | 依赖 | 验证方法 |
|---|------|------|------|------|----------|
| C1 | Win7 客户端子模块镜像 | `client/zotero-standalone-build-win7/` | 同步 `zotero-standalone-build` @ `5.0.96.3` tag | git submodule | `git submodule status` |
| C2 | Win7 客户端源码镜像 | `client/zotero-client-win7/` | 同步 `zotero-client` @ 5.0.96.3 同期 commit | git submodule | `cat version` |
| C3 | Win7 专用 Dockerfile | `prebuild_client_win7.Dockerfile` + `clientbuildtest_win7.Dockerfile` | 拉取并打 5.0.96.3 Windows 安装包 | C1, C2, Docker | `docker build` 产出 .exe |
| C4 | 构建开关 + 探测脚本 | `bin/build-local.sh`（增 `WIN7=1`）+ `bin/detect-win-version.sh`（新增） | 决定构建哪个客户端 + 按 Windows 版本选安装包 | C3, `os` 命令 | shellcheck + bats |
| C5 | 内网部署包/文档 | `bin/package-for-intranet.sh`（改）+ `clients-manifest.json`（新）+ `docs/technical/18-win7-compatibility.md`（新）+ `docs/user-manual/09-win7-installation.md`（新） | 打包两个客户端 + 写明 Win7 安装步骤 | C3, C4 | 文档链接有效、脚本退出码 0 |
| C6 | dataserver URL 注入（双保险） | `prebuild_client_win7.Dockerfile` 内的 XPI 解包+改+`makensis` 重打包（A' 主路径） + `bin/set-zotero-dataserver.ps1`（C 兜底路径） | 构建期主注入 + 部署后兜底注入 | C3, 7z, makensis, PowerShell 5.x | 构建产物 .exe 装到 Win7 后同步 dataserver 正确 |

### 4.1 C1 + C2 取舍：submodule 而非 subtree / fork

- **submodule**：与现有 `client/*` 子模块平级，`.gitmodules` 一行加一项。**内网环境**由 `package-for-intranet.sh` 把 `client/.git/modules/` 一起 vendor 进去。
- ~~subtree~~：merge/rebase 体验差，命令复杂。
- ~~fork 分支~~：后续 dataserver/Docker/K8s 改动无法回流到 win7 分支，长期 drift。

### 4.2 C4 关键代码（伪代码）

```bash
# bin/build-local.sh 增量
WIN7="${WIN7:-0}"
if [ "$WIN7" = "1" ]; then
    DOCKERFILE="prebuild_client_win7.Dockerfile"
    TARGET_TAG="zotprime-client:win7-5.0.96.3"
    REQUIRED_VERSION="5.0.96.3"
else
    DOCKERFILE="prebuild_client.Dockerfile"
    TARGET_TAG="zotprime-client:latest"
    REQUIRED_VERSION="8.0.1"
fi
```

```bash
# bin/detect-win-version.sh 契约
# 输入: 无（--probe 模式调 wmic）或 stdin 一行 ver 输出
# 输出: 单行 win11|win10|win8|win7|xp|unknown
# 退出码: 0=识别, 1=unknown, 2=工具不可用
# 副作用: stderr 一行 ISO8601 日志
```

## 5. 接口契约

### 5.1 接口 1：构建入口（环境变量）

| 变量 | 默认 | 说明 |
|------|------|------|
| `WIN7` | `0` | `1`=构建 Win7 版；`0`=构建现代版 |
| `CLIENT_VERSION` | 读 `zotero-client/version` | 现代版版本号 |
| `CLIENT_WIN7_VERSION` | `5.0.96.3` | Win7 版版本号（固定） |
| `DIST_DIR` | `./dist` | 产物输出目录 |
| `SIGNTOOL` | 空 | Windows 代码签名工具路径（空=跳过签名） |

退出码：`0`=成功；`1`=Docker 构建失败；`2`=签名失败；`3`=版本号校验失败；`10~13` 见错误处理章节。

### 5.2 接口 2：探测脚本（stdin/stdout）

```
输入: 无（--probe）或 stdin 一行 ver 输出
输出: 单行 win11 | win10 | win8 | win7 | xp | unknown
退出码: 0 | 1 | 2
stderr: ISO8601 时间戳 + 探测路径
```

### 5.3 接口 3：内网包清单（JSON Schema）

```jsonc
// clients-manifest.json
{
  "version": "v3.3.0",
  "clients": {
    "win10plus": {
      "installer": "clients/win10plus/Zotero-8.0.1_win-x86_64-setup.exe",
      "sha256": "<hex>",
      "min_os": "10.0",
      "arch": ["x86_64"]
    },
    "win7": {
      "installer": "clients/win7/Zotero-5.0.96.3_win-x86_64-setup.exe",
      "sha256": "<hex>",
      "min_os": "6.1",
      "arch": ["x86_64", "x86"]
    }
  }
}
```

Schema 校验：`tests/integration/manifest-schema.json`（JSON Schema draft-07）。

### 5.4 接口 4：dataserver 兼容性（无需改）

- 5.0 客户端 ↔ 8.0 dataserver：协议兼容（Zotero 5.0 同步协议在 5.0~7.0 dataserver 上未变）
- 5.0 客户端不支持 PDF 内置阅读器、标签 v2、新笔记格式 → dataserver 返回时 5.0 客户端忽略，无副作用
- 8.0 客户端读 5.0 写过的字段安全（5.0 字段集 ⊂ 8.0 字段集）

## 6. 错误处理

### 6.1 错误码契约

| 退出码 | 名称 | 触发条件 | 用户可见信息 |
|--------|------|----------|--------------|
| 0 | OK | 成功 | - |
| 1 | DOCKER_BUILD_FAIL | Dockerfile 构建失败 | "Docker 构建失败，详见 dist/build.log" |
| 2 | SIG_FAIL | 代码签名失败 | "签名失败，是否缺少 SIGNTOOL 证书？" |
| 3 | VERSION_MISMATCH | zotero-client-win7/version ≠ 5.0.96.3 | "Win7 子模块版本应为 5.0.96.3，实际为 X" |
| 10 | ENV_MISSING | WIN7=1 但子模块未初始化 | "请先执行 git submodule update --init ..." |
| 11 | DOCKER_BUILD_FAIL_V2 | 同 1，区分 bash 层与 docker 层 | 同 1 |
| 12 | SUBMODULE_VERSION | 子模块 ref 不在预期 commit | 同 3 |
| 13 | SIG_FAIL_V2 | 同 2 | 同 2 |
| 20 | INTRANET_PACKAGE_FAIL | 缺任一客户端产物 | "请先运行 WIN7=1 bin/build-local.sh 与默认构建" |
| 30 | WIN_VERSION_UNSUPPORTED | detect 输出 unknown | "无法识别 Windows 版本，请联系运维手动选包" |
| 31 | INTEGRITY_FAIL | sha256 校验失败 | "安装包校验失败，请重新下载" |
| 32 | NOT_WIN7 | 用户在 Win7 跑了 win10plus 包 | "此安装包不适用于 Win7，请改用 5.0.96.3" |

### 6.2 失败恢复策略

**构建期（DOCKER_BUILD_FAIL = 11）**

- 保留 `dist/build.log` 完整输出
- 自动运行 `docker system prune --filter label=zotprime-test --force` 清理中间层
- 退出码 11

**打包期（INTRANET_PACKAGE_FAIL = 20）**

- 检查 `dist/` 目录是否存在 `Zotero-{8.0.1,5.0.96.3}_*.exe`
- 给出"缺哪个、补哪个"的具体提示
- **不**自动跳过（避免部署包残缺）
- 退出码 20

**部署期（WIN_VERSION_UNSUPPORTED = 30）**

- 默认分发 win10plus 包
- 部署日志标记 `MANUAL_CHECK_REQUIRED`
- 退出码 0（不阻塞部署）
- 运维事后人工确认

**运行期（NSIS NOT_WIN7 = 32）**

- 安装器检测到 OS < 6.2 时弹窗提示（中文）
- 继续安装不阻塞，写 `install.log` 一行 WARN
- 启动后第一次连 dataserver 时输出 "您使用的是 Zotero 5，部分新功能不可用"

### 6.3 错误信息国际化

| 受众 | 语言 |
|------|------|
| 构建/部署错误 | 英文（便于搜索） |
| NSIS 安装器弹窗 | 中文（内网用户群） |
| Zotero 内部提示 | 跟随 5.0.96.3 自带 zh-CN |

### 6.4 不可恢复错误兜底

```bash
trap 'echo "[FATAL] Unexpected error at line $LINENO. Dist: $DIST_DIR. Log: $DIST_DIR/build.log" >&2' ERR
```

### 6.5 dataserver URL 注入（C6，双保险：A' 主 + C 兜底）

**A' 主路径：构建期 XPI 重打包 + makensis 重编译**

`prebuild_client_win7.Dockerfile` 内的注入序列：

```dockerfile
ARG WIN7_VERSION=5.0.96.3
ARG HOST_DS=http://zotprime.local:8080/
ARG HOST_ST=ws://zotprime.local:8081/

# 1. 拉官方 5.0.96.3 Windows setup.exe
RUN curl -L -o /tmp/zotero-setup.exe \
    https://download.zotero.org/client/release/${WIN7_VERSION%.*}/Zotero-${WIN7_VERSION}_win-x86_64-setup.exe

# 2. 7z 解 NSIS 自解压包
RUN 7z x -y -o/opt/zotero_build /tmp/zotero-setup.exe

# 3. 定位 Zotero 扩展 XPI（多路径候选，适配 5.0 时代不同安装布局）
RUN ZOTERO_XPI=$(find /opt/zotero_build -name "zotero@chnm.org.xpi" | head -1) && \
    test -n "$ZOTERO_XPI" || { echo "[FATAL] XPI not found" >&2; exit 12; } && \
    echo "Found XPI: $ZOTERO_XPI"

# 4. 解 XPI → sed config.js → 7z 重打包
RUN mkdir -p /opt/xpi_work && cd /opt/xpi_work && \
    7z x -y "$ZOTERO_XPI" && \
    test -f resource/config.js || { echo "[FATAL] config.js not in XPI" >&2; exit 12; } && \
    sed -i "s|https://api.zotero.org|${HOST_DS}|g" resource/config.js && \
    sed -i "s|wss://stream.zotero.org|${HOST_ST}|g" resource/config.js && \
    rm -f "$ZOTERO_XPI" && \
    7z a -tzip -mx=9 "$ZOTERO_XPI" .

# 5. makensis 重编译 NSIS 安装包
RUN cp /opt/zotero_build/installer.nsi /opt/ && \
    cd /opt && makensis installer.nsi && \
    cp setup.exe /dist/Zotero-${WIN7_VERSION}_win-x86_64-setup.exe && \
    sha256sum /dist/Zotero-${WIN7_VERSION}_win-x86_64-setup.exe \
        | awk '{print $1}' > /dist/Zotero-${WIN7_VERSION}_win-x86_64-setup.exe.sha256
```

**关键决策（已采纳）：**

| 取舍 | 决策 | 理由 |
|------|------|------|
| 解 NSIS 改 XPI 后用 `makensis` 重打包 | ✅ 采用 | 7zSFX 重新组装会丢失 NSIS 宏（`$PLUGINSDIR` 等），安装时崩；makensis 才是 5.0 时代的标准 NSIS 编译器 |
| sed 替换 `https://api.zotero.org` → `${HOST_DS}` | ✅ 采用 | 与现代版 `prebuild_client.Dockerfile:31-35` 的 sed 规则 1/3 对称 |
| sed 替换 `wss://stream.zotero.org` → `${HOST_ST}` | ✅ 采用 | 与现代版 sed 规则 2 对称 |
| 不动 `https://www.zotero.org/`（规则 3） | ✅ 采用 | Win7 客户端不内置浏览器主页，不需要替换 |
| 不动 proxy check URL（规则 4） | ✅ 采用 | 5.0 时代 Zotero 不会调用 proxy check |
| HOST_DS 默认 `http://zotprime.local:8080/` | ✅ 采用 | 跟现代版 ARG 默认值风格一致 |
| 不内嵌 7za.exe 到 NSIS 包 | ✅ 采用 | 注入全部在构建期完成，运行时不需要 7z |
| 失败时保留 `/opt/zotero_build` 供调试 | ✅ 采用 | 退出码 12 时 `docker cp` 可提取 |

**C 兜底路径：部署后 PowerShell 注入**

`bin/set-zotero-dataserver.ps1` 关键逻辑：

```powershell
param(
    [string]$InstallPath = "${env:ProgramFiles}\Zotero",
    [string]$DataServerUrl = "http://zotprime.local:8080/",
    [string]$StreamServerUrl = "ws://zotprime.local:8081/"
)
$ErrorActionPreference = "Stop"

# 定位 XPI（多路径候选）
$xpiCandidates = @(
    "$InstallPath\distribution\extensions\zotero@chnm.org.xpi",
    "$env:APPDATA\Zotero\Zotero\profiles\*\extensions\zotero@chnm.org.xpi"
)
$xpi = $xpiCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $xpi) { Write-Error "Zotero XPI not found"; exit 1 }

# 备份
$bak = "$xpi.bak.$(Get-Date -Format yyyyMMddHHmmss)"
Copy-Item -Path $xpi -Destination $bak -Force

# 用 System.IO.Compression 改 zip
$tempDir = Join-Path $env:TEMP "zotero-xpi-$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($xpi, $tempDir)

# 改 config.js
$configJs = Join-Path $tempDir "resource\config.js"
$content = Get-Content $configJs -Raw
$content = $content -replace 'https://api\.zotero\.org', $DataServerUrl
$content = $content -replace 'wss://stream\.zotero\.org', $StreamServerUrl
[System.IO.File]::WriteAllText($configJs, $content, [System.Text.Encoding]::UTF8)

# 重打包
Remove-Item -Path $xpi -Force
[System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $xpi)
Remove-Item -Recurse -Path $tempDir

Write-Host "Zotero dataserver set to: $DataServerUrl (backup: $bak)"
```

**PowerShell 兼容性矩阵：**

| Win7 PS 版本 | 默认包含 | `System.IO.Compression` | 备注 |
|--------------|----------|--------------------------|------|
| 2.0（默认） | ❌ 缺 ZipFile API | 需 fallback 到 `Shell.Application` | 路径复杂，回退方案见 6.5.1 |
| 3.0 | ❌ | 同上 | |
| 4.0 | ❌ | 同上 | |
| **5.0+** | ✅ `System.IO.Compression.FileSystem` | 直接用 | 需安装 WMF 5.1 |

→ **A' 主路径**已经把 dataserver 注入构建期完成，**C 兜底路径只在 A' 失败时使用**（运维 push 修补），所以兜底路径的兼容性要求可放松。

**6.5.1 C 路径的 PS 2.0 fallback（仅兜底时使用）：**

```powershell
# PS 2.0 缺 System.IO.Compression，改用 Shell.Application (zip 文件夹能力有限)
$shell = New-Object -ComObject Shell.Application
$folder = $shell.Namespace((Split-Path $xpi))
# ... Shell.Application 处理 zip 不可靠，建议直接告知用户升级 PS 5.1
Write-Warning "PowerShell < 5.0 detected, please install WMF 5.1 or use A' build path"
exit 3
```

**6.5.2 注入正确性验证（无论 A' 还是 C）：**

装到 Win7 后第一次启动 Zotero 5.0.96.3，访问 `about:config`（地址栏输入）查以下 pref：

```
extensions.zotero.{...}.API_URL  → 期望等于 ${HOST_DS}
```

（pref key 实际是 `extensions.zotero.<addon-id>.API_URL`，需在装机后用 `about:config` 查；注入失败的特征是仍为 `https://api.zotero.org/`。）

## 7. 测试策略

### 7.1 测试矩阵

| 层 | 工具 | 范围 | 自动化 | 触发 |
|----|------|------|--------|------|
| L1 静态 | shellcheck + bashate | 所有新 .sh | ✅ | PR / pre-commit |
| L2 单元 | bats-core | detect-win-version.sh, build-local.sh 分支 | ✅ | PR / pre-commit |
| L3 契约 | jq + diff | clients-manifest.json schema | ✅ | PR / pre-commit |
| L4 集成 | Docker | Dockerfile 产出 .exe + sha256 匹配 | ✅ | nightly + 标记 `win7-build` |
| L5 子模块 | git submodule | 切到 5.0.96.3 后关键文件存在 | ✅ | PR |
| L6 协议 | curl | dataserver 对 5.0 client 协议返回正常 | ✅ | nightly |
| L7 E2E | 手动 | Win7 SP1 VM 双击安装 + 启动 + 同步 | ❌ 手动 | 里程碑前 |

### 7.2 单元测试样例

**`tests/bin/detect-win-version.bats`**

```bash
@test "recognizes Windows 7 from ver output" {
    run bash -c "echo 'Microsoft Windows [Version 6.1.7601]' | $SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "win7" ]
}
# ... win10 / win11 / unknown / --probe 失败 4 个用例
```

**`tests/bin/build-local.bats`**

```bash
@test "WIN7=1 selects win7 dockerfile" {
    WIN7=1 run bash -c "source $SCRIPT --dry-run"
    [[ "$output" == *"prebuild_client_win7.Dockerfile"* ]]
}
# ... 默认 / 缺子模块 2 个用例
```

### 7.3 子模块测试

```bash
# tests/submodule/win7-refs.bats
@test "zotero-standalone-build-win7 points to 5.0.96.3" {
    cd client/zotero-standalone-build-win7
    [ "$(git describe --tags --exact-match)" = "5.0.96.3" ]
}
```

### 7.4 协议兼容测试（nightly）

```bash
curl -X POST "$DATASERVER/items" \
    -H "User-Agent: Zotero/5.0.96.3 (Win7)" \
    -H "Zotero-API-Key: $TEST_KEY" \
    --data @tests/fixtures/sync-request-5.0.xml | grep -q "<response>"
```

### 7.5 端到端（手动 checklist，Win7 SP1 Vagrant VM）

- [ ] 干净环境安装 5.0.96.3 安装包成功
- [ ] 首次启动不报"缺少 dll"
- [ ] 配同步连到 ZotPrime dataserver，上传一条文献
- [ ] 在 Win10 客户端登录同一账号，能看到该条文献
- [ ] 反向：Win10 添加一条，Win7 同步下来
- [ ] Word 集成（zotero-win32-transfw）正常
- [ ] 卸载干净，无残留注册表

### 7.6 覆盖目标

- 脚本代码：80%+（kcov + bats）
- NSIS 字符串：100%（grep 验证所有新 MinSupportedVer）
- API 兼容：5.0 关键 20 个 endpoint

### 7.7 不在测试范围

- 5.0 客户端在 Win7 的 PDF 阅读性能
- 国际化翻译完整性
- 32 位 Win7

## 8. 实施步骤

**分支基线：`feature/win7-compatibility`（从 develop 拉）**

### M0：分支 + 子模块基线（1 天）

- [x] 拉新分支（已完成）
- [ ] 添加 2 个子模块占位
- [ ] `.gitmodules` 提交
- [x] 写本设计稿并提交

### M1：构建链路（4 天，含 A' dataserver 注入）

- [ ] `prebuild_client_win7.Dockerfile`：复用 `prebuild_client.Dockerfile`，改 URL 为 `https://download.zotero.org/client/release/5.0.96.3/Zotero-5.0.96.3_win-x86_64-setup.exe`
- [ ] `clientbuildtest_win7.Dockerfile`
- [ ] 改 `bin/build-local.sh`：加 `WIN7=1` 分支
- [ ] 加错误码 10/11/12/13 处理
- [ ] **A' 主路径**：在 `prebuild_client_win7.Dockerfile` 内集成 XPI 解包+`resource/config.js` sed 注入+`makensis` 重打包流水线（详见 §6.5）
- [ ] 实机验证：拉一份 5.0.96.3 setup.exe → 解 → 注入 → makensis 重打包 → 在 Win7 SP1 装 → 启 Zotero → `about:config` 查 `extensions.zotero.<id>.API_URL` 已是内网地址

### M2：探测 + 打包（3 天，含 C 兜底注入）

- [ ] 写 `bin/detect-win-version.sh`
- [ ] 改 `bin/package-for-intranet.sh`：纳入 `clients/{win10plus,win7}/`，生成 `clients-manifest.json`
- [ ] 写 `tests/bin/*.bats` 与 `tests/integration/*.bats`
- [ ] `bats tests/` 全绿
- [ ] **C 兜底路径**：写 `bin/set-zotero-dataserver.ps1`（含 PS 2.0 fallback 警告），A' 失败时由运维 push 调用
- [ ] 改 `bin/deploy-intranet.sh`：检测 Win7 + A' 注入失败时，提示"将推送 PowerShell 兜底脚本"

### M3：文档 + E2E（2 天）

- [ ] `docs/technical/18-win7-compatibility.md`
- [ ] `docs/user-manual/09-win7-installation.md`
- [ ] 更新 `docs/technical/README.md` 与 `docs/user-manual/README.md` 章节目录
- [ ] Vagrant 拉 Win7 SP1 镜像，跑 7.5 E2E 清单
- [ ] 跑 dataserver 协议兼容测试

**总工期：10 工作日（≈ 2 周）**

## 9. 风险评估

| ID | 风险 | 等级 | 概率 | 影响 | 缓解 |
|----|------|------|------|------|------|
| R1 | 5.0.96.3 子模块在内网拉取失败 | HIGH | 中 | 构建失败 | package-for-intranet.sh vendor .git/modules/；M1 先有网环境验 |
| R2 | 5.0.96.3 客户端与 8.0.1 dataserver 协议不兼容 | MEDIUM | 低 | 5.0 同步报 4xx | M3 跑协议测试；如失败回退需降 dataserver（超出范围） |
| R3 | NSIS 安装器在 Win7 缺 VC++ 运行库 | HIGH | 中 | 启动崩"缺 MSVCR120.dll" | Dockerfile 预装 VC++ 2013 Redist；M3 E2E 在干净 Win7 验 |
| R4 | 内网用户机器是 XP/Server 2008 | MEDIUM | 中 | 安装失败无清晰提示 | detect 加 xp/2003/2008 分支，引导升级 |
| R5 | Gecko 60 ESR Win7 安全补丁停止 | LOW | 已发生 | Win7 客户端有 CVE 风险 | 文档声明"仅建议内网隔离环境" |
| R6 | 5.0 ↔ 8.0 字段集差异致覆盖丢数据 | MEDIUM | 低 | Win10 端少字段 | dataserver 端加 5.0 客户端只写不覆盖（业务侧） |
| R7 | 5.0.96.3 维护冻结，数月后协议升级断 5.0 客户端 | HIGH | 长期 | 5.0 同步失效 | 文档声明"5.0 客户端冻结于 2026-06-07 协议版本" |
| R8 | CI 构建超时（5.0.96.3 依赖老 Node/Python） | MEDIUM | 中 | CI 红 | 独立 `win7-build` workflow，timeout 30min |
| R9 | 5.0.96.3 setup.exe 内 NSIS 内部布局与官方不一致（5.0 时代有多个 minor 变体） | MEDIUM | 中 | `find ... -name "zotero@chnm.org.xpi"` 找不到 → 退出码 12 | 多路径候选（distribution/extensions/, App/Zotero/distribution/extensions/）+ 实机验证 5.0.96.3 唯一 tag |
| R10 | `makensis` 在 Linux 容器内重打包 Windows NSIS 安装包失败（路径/编码问题） | MEDIUM | 中 | A' 注入失败 | Dockerfile 选 `iurt-the-catalyst/nsis:3.09` 镜像；失败时保留 `installer.nsi` 与中间产物供调试 |
| R11 | Zotero 5.0 启动时校验 XPI 完整性（hash 比对） | LOW | 低 | 注入后的 XPI 被 Zotero 拒载，dataserver 仍为 zotero.org | M1 实机验证 + 用 `prefs.js` 注入双保险（如 XPI 校验） |
| R12 | PowerShell 兜底路径在 Win7 SP1 默认 PS 2.0 下 `System.IO.Compression` 缺失 | LOW | 中 | C 路径无法使用 | 检测 PS 版本 < 5.0 时给出明确错误，引导安装 WMF 5.1 或重新跑 A' 构建 |

## 10. 回滚方案

若 M0~M3 任意阶段发现不可行：

```bash
git checkout develop
git branch -D feature/win7-compatibility
git submodule deinit -f client/zotero-standalone-build-win7 client/zotero-client-win7
git checkout develop -- .gitmodules
```

内网部署包不破坏 v3.2.0 既有结构（只新增 `clients/` 目录与 manifest 字段）。

## 11. 附录

### 11.1 关键文件路径速查

| 用途 | 路径 |
|------|------|
| Win7 子模块构建 | `client/zotero-standalone-build-win7/` |
| Win7 客户端源码 | `client/zotero-client-win7/` |
| Win7 Dockerfile | `prebuild_client_win7.Dockerfile` |
| Win7 构建测试 | `clientbuildtest_win7.Dockerfile` |
| 构建入口 | `bin/build-local.sh` |
| 版本探测 | `bin/detect-win-version.sh` |
| 内网打包 | `bin/package-for-intranet.sh` |
| 内网部署 | `bin/deploy-intranet.sh` |
| 包清单 | `clients-manifest.json` |
| 技术文档 | `docs/technical/18-win7-compatibility.md` |
| 用户文档 | `docs/user-manual/09-win7-installation.md` |
| 本设计稿 | `docs/superpowers/specs/2026-06-07-win7-compatibility-design.md` |
| 测试目录 | `tests/{bin,integration,submodule}/` |
| A' XPI 注入脚本 | `prebuild_client_win7.Dockerfile` 内 inline（解 7z + sed + 7z + makensis） |
| C 兜底 PowerShell | `bin/set-zotero-dataserver.ps1` |

### 11.2 调研依据

- 现状：zotprime 当前使用 Gecko 60.9.0esr 链（非 Electron 链）
- 5.0.96.3 是 Zotero 最后一个官方明确支持 Win7 的版本
- Firefox 60 ESR 官方最低支持 Win7 SP1
- 8.0.1 源码 + Gecko 60 ESR 兼容性未官方背书

### 11.3 关键决策记录（ADR-lite）

- **2026-06-07**：选用方案 C（双版本并行），不用方案 A/B。
- **2026-06-07**：用 submodule 而非 subtree/fork。
- **2026-06-07**：5.0.96.3 固定，不再跟随 6.0+ 更新（避免无止境的 backport）。
- **2026-06-07**：不在 dataserver 端加 5.0 兼容代码（保持上游兼容）。
- **2026-06-07**：dataserver URL 注入选 A'（构建期 XPI 重打包 + makensis）+ C（部署后 PowerShell 兜底）双保险路径，不用 B（NSIS post-install，侵入 5.0 子模块）与 D（启动器+env，需 fork 5.0 源码）。
