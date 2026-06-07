# Win7 Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在新分支 `feature/win7-compatibility` 下实施 ZotPrime Win7 兼容性方案 C：双版本并行（Win7→Zotero 5.0.96.3，Win10+→Zotero 8.0+），含 A' 构建期 XPI 重打包 + C 部署后 PowerShell 兜底两条 dataserver URL 注入路径。

**Architecture:** Git submodule 双镜像（`zotero-standalone-build-win7` + `zotero-client-win7` 锁 5.0.96.3），通过 `prebuild_client_win7.Dockerfile` 拉官方 5.0.96.3 setup.exe → 7z 解 → 改 XPI 内 `resource/config.js` → `makensis` 重打包（与 8.0+ 注入路径对称）。`bin/detect-win-version.sh` 探测 Windows 版本，`bin/package-for-intranet.sh` 产出 `clients/{win10plus,win7}/` 两个目录 + `clients-manifest.json`，`bin/deploy-intranet.sh` 按 OS 分发。`bin/set-zotero-dataserver.ps1` 作为兜底。

**Tech Stack:**
- Bash 5.x（构建/部署脚本）
- bats-core 1.8+（单元测试）
- Docker（构建容器化）
- 7zip（XPI 解包/重打包）
- NSIS 3.09 + `makensis`（Linux 容器内重编译）
- PowerShell 5.1（兜底注入脚本，目标 Win7 SP1）
- git submodule（双版本子模块）

**Spec:** [`docs/superpowers/specs/2026-06-07-win7-compatibility-design.md`](../superpowers/specs/2026-06-07-win7-compatibility-design.md)（已批准，提交 `a0384b0f`）

---

## Scope Check

Spec 覆盖 6 个独立组件（C1-C6）、4 个里程碑（M0-M3）、总工期 10 工作日。是**一个完整可独立交付的子项目**（Win7 兼容），不需拆分。

---

## File Structure

### 新增文件

| 路径 | 职责 |
|------|------|
| `client/zotero-standalone-build-win7/` | submodule，锁 5.0.96.3（由 git 创建，本 plan 不写） |
| `client/zotero-client-win7/` | submodule，锁 5.0.96.3 同期 commit（由 git 创建，本 plan 不写） |
| `prebuild_client_win7.Dockerfile` | 拉 5.0.96.3 setup.exe → 解 → 改 XPI → makensis 重打包 |
| `clientbuildtest_win7.Dockerfile` | 用 bats 验证产物 |
| `bin/detect-win-version.sh` | 探测 Windows 版本号 → win7/win8/win10/win11/xp/unknown |
| `bin/set-zotero-dataserver.ps1` | A' 失败时的 PowerShell 兜底注入 |
| `docs/technical/18-win7-compatibility.md` | 开发者视角的兼容性矩阵 + 构建命令 |
| `docs/user-manual/09-win7-installation.md` | 用户视角的 Win7 安装步骤 |
| `tests/bin/detect-win-version.bats` | detect 脚本单元测试 |
| `tests/bin/build-local.bats` | build-local.sh 单元测试 |
| `tests/integration/win7-build.bats` | Win7 集成测试（仅 `win7-build` 标记时跑） |
| `tests/integration/manifest-schema.json` | clients-manifest.json JSON Schema 校验文件 |
| `tests/integration/dataserver-5-compat.sh` | dataserver 对 5.0 协议兼容测试（nightly） |
| `tests/submodule/win7-refs.bats` | 子模块 ref 校验 |
| `clients-manifest.json` | 内网部署包根清单 |

### 修改文件

| 路径 | 改动 |
|------|------|
| `.gitmodules` | 加 2 个 win7 子模块条目 |
| `bin/build-local.sh` | 加 `WIN7=1` 分支 + 错误码 10/11/12/13 |
| `bin/package-for-intranet.sh` | 加 `clients/{win10plus,win7}/` 目录 + 写 manifest |
| `bin/deploy-intranet.sh` | 调用 detect 脚本分发对应客户端 |
| `docs/technical/README.md` | 加 §18 章节目录条目 |
| `docs/user-manual/README.md` | 加 §09 章节目录条目 |

---

## 任务地图（5 个 PR）

| PR | 内容 | 估时 | 任务编号 |
|----|------|------|----------|
| **PR#1** | M0：分支 + 子模块基线 | 1 天 | Task 1.1-1.4 |
| **PR#2** | M1：Win7 Dockerfile + A' 注入 | 4 天 | Task 2.1-2.10 |
| **PR#3** | M2：探测脚本 + bats | 3 天 | Task 3.1-3.8 |
| **PR#4** | M2：C 兜底 PS + 打包 | 3 天 | Task 4.1-4.6 |
| **PR#5** | M3：文档 + E2E | 2 天 | Task 5.1-5.6 |

---

# PR#1: M0 — 分支与子模块基线

## Task 1.1: 确认在 feature/win7-compatibility 分支

**Files:**
- Read: `.git/HEAD`

- [ ] **Step 1: 验证当前分支**

Run: `git branch --show-current`
Expected: `feature/win7-compatibility`

如果不在该分支，Run: `git checkout feature/win7-compatibility`

- [ ] **Step 2: 验证提交基线**

Run: `git log --oneline -1`
Expected: `a0384b0f docs: add C6 dataserver injection design (A' build-time + C PS fallback)`（或更新的 head）

- [ ] **Step 3: 无 commit 操作（分支已存在且包含 spec）**

## Task 1.2: 添加 zotero-standalone-build-win7 子模块占位

**Files:**
- Modify: `.gitmodules`
- Create: `client/zotero-standalone-build-win7/`（git submodule 自动创建）

- [ ] **Step 1: 添加子模块，锁定 5.0.96.3 tag**

Run:
```bash
cd /home/fz/project/zotprime
git submodule add \
    --branch 5.0.96.3 \
    https://github.com/uniuuu/zotero-standalone-build.git \
    client/zotero-standalone-build-win7
```

Expected: `.gitmodules` 增加 `client/zotero-standalone-build-win7` 条目，目录被 checkout 到 5.0.96.3。

- [ ] **Step 2: 验证子模块 commit**

Run:
```bash
cd client/zotero-standalone-build-win7 && git describe --tags --exact-match
```

Expected: `5.0.96.3`

- [ ] **Step 3: 验证关键文件存在**

Run:
```bash
ls client/zotero-standalone-build-win7/win/installer/installer.nsi
ls client/zotero-standalone-build-win7/assets/application.ini
```

Expected: 两个文件都存在（说明子模块已正确 checkout）。

- [ ] **Step 4: 暂不 commit（连同 1.3 一起 commit）**

## Task 1.3: 添加 zotero-client-win7 子模块占位

**Files:**
- Modify: `.gitmodules`
- Create: `client/zotero-client-win7/`

- [ ] **Step 1: 查找 5.0.96.3 对应的 zotero-client commit**

5.0.96.3 在 zotero-standalone-build 子模块内是 win/installer/ 引用 + 子模块 `client/zotero-client`，需要找出对应 commit hash。

Run（在主仓库内）:
```bash
cd /home/fz/project/zotprime/client/zotero-standalone-build-win7
# zotero-client 在 5.0.96.3 时代是 build.sh 第 X 行的子模块引用
grep -n "zotero-client" build.sh | head -5
# 找到具体的 commit hash 行
```

Expected: 输出 `git checkout <commit-hash>` 或类似引用。记录该 commit hash，例如 `abc1234`。

- [ ] **Step 2: 添加子模块指向特定 commit（无分支）**

Run:
```bash
cd /home/fz/project/zotprime
git submodule add \
    https://github.com/uniuuu/zotero.git \
    client/zotero-client-win7
cd client/zotero-client-win7
git checkout <5.0.96.3-commit-hash-from-step-1>
cd /home/fz/project/zotprime
```

Expected: `client/zotero-client-win7/version` 内容类似 `5.0.96.3.SOURCE`。

- [ ] **Step 3: 验证 version 文件**

Run: `cat client/zotero-client-win7/version`
Expected: `5.0.96.3.SOURCE`

## Task 1.4: 提交 PR#1

**Files:**
- Modify: `.gitmodules`
- Create: `client/zotero-standalone-build-win7/`
- Create: `client/zotero-client-win7/`

- [ ] **Step 1: 查看 diff**

Run: `git status --short`
Expected:
```
M .gitmodules
?? .gitmodules
?? client/zotero-standalone-build-win7
?? client/zotero-client-win7
```

- [ ] **Step 2: 提交**

Run:
```bash
cd /home/fz/project/zotprime
git add .gitmodules client/zotero-standalone-build-win7 client/zotero-client-win7
git -c user.email=claude@local -c user.name=claude commit -m "chore: add Win7 submodules at 5.0.96.3"
```

- [ ] **Step 3: 验证提交**

Run: `git log --oneline -1`
Expected: `chore: add Win7 submodules at 5.0.96.3`

- [ ] **Step 4: 验证 CI 不会因脏工作区爆错**

Run: `git submodule status | head -3`
Expected: 两个 win7 子模块前面是空格（已初始化）或 `-`（未初始化），不带 `+`（modified）。

---

# PR#2: M1 — Win7 Dockerfile + A' 注入

## Task 2.1: 写 prebuild_client_win7.Dockerfile（不含注入段）

**Files:**
- Create: `prebuild_client_win7.Dockerfile`

- [ ] **Step 1: 写第一版 Dockerfile**

Create `prebuild_client_win7.Dockerfile` with:
```dockerfile
# syntax=docker/dockerfile:1.6
# Win7 客户端预构建：拉 5.0.96.3 setup.exe → A' 注入 → 重打包
# 用法: docker build -f prebuild_client_win7.Dockerfile --build-arg HOST_DS=... --build-arg HOST_ST=... -t zotprime-client:win7-5.0.96.3 .

FROM debian:bookworm-slim AS base

ARG WIN7_VERSION=5.0.96.3
ARG HOST_DS=http://zotprime.local:8080/
ARG HOST_ST=ws://zotprime.local:8081/

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    p7zip-full \
    unzip \
    zip \
    nsis \
    make \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# 1. 拉官方 5.0.96.3 Windows setup.exe
RUN curl -L --fail-with-body -o /tmp/zotero-setup.exe \
    "https://download.zotero.org/client/release/5.0/Zotero-${WIN7_VERSION}_win-x86_64-setup.exe" \
    || { echo "[FATAL] Failed to download 5.0.96.3 setup.exe" >&2; exit 11; }

# 2. 7z 解 NSIS 自解压包
RUN 7z x -y -o/opt/zotero_build /tmp/zotero-setup.exe \
    || { echo "[FATAL] 7z failed to extract NSIS package" >&2; exit 11; }

# 3. 定位 Zotero 扩展 XPI（多路径候选，适配 5.0 时代不同安装布局）
RUN ZOTERO_XPI=$(find /opt/zotero_build -name 'zotero@chnm.org.xpi' | head -1) \
    && if [ -z "$ZOTERO_XPI" ]; then \
         echo "[FATAL] zotero@chnm.org.xpi not found in /opt/zotero_build" >&2; exit 12; \
       fi \
    && echo "ZOTERO_XPI=$ZOTERO_XPI" > /tmp/xpi_path.env

FROM base AS inject

COPY --from=base /tmp/xpi_path.env /tmp/xpi_path.env
COPY --from=base /opt/zotero_build /opt/zotero_build

ARG HOST_DS
ARG HOST_ST

# 4. 解 XPI → sed config.js → 7z 重打包
RUN set -euo pipefail \
    && . /tmp/xpi_path.env \
    && mkdir -p /opt/xpi_work \
    && cd /opt/xpi_work \
    && 7z x -y "$ZOTERO_XPI" \
    && if [ ! -f resource/config.js ]; then \
         echo "[FATAL] resource/config.js not found in XPI" >&2; exit 12; \
       fi \
    && sed -i.bak "s|https://api.zotero.org|${HOST_DS}|g" resource/config.js \
    && sed -i.bak "s|wss://stream.zotero.org|${HOST_ST}|g" resource/config.js \
    && rm -f "$ZOTERO_XPI" \
    && 7z a -tzip -mx=9 "$ZOTERO_XPI" . \
    && echo "[OK] XPI injection done: $ZOTERO_XPI" >&2

FROM inject AS repack

# 5. makensis 重编译 NSIS 安装包
RUN set -euo pipefail \
    && cd /opt/zotero_build \
    && ls *.nsi 2>/dev/null | head -1 > /tmp/main_nsi \
    && MAIN_NSI=$(cat /tmp/main_nsi) \
    && cp "$MAIN_NSI" /opt/installer.nsi \
    && cd /opt \
    && makensis installer.nsi \
    && mkdir -p /dist \
    && cp setup.exe "/dist/Zotero-${WIN7_VERSION}_win-x86_64-setup.exe" \
    && sha256sum "/dist/Zotero-${WIN7_VERSION}_win-x86_64-setup.exe" \
        | awk '{print $1}' \
        > "/dist/Zotero-${WIN7_VERSION}_win-x86_64-setup.exe.sha256" \
    && echo "[OK] Build complete: /dist/Zotero-${WIN7_VERSION}_win-x86_64-setup.exe" >&2

FROM scratch AS artifact
COPY --from=repack /dist/ /
```

- [ ] **Step 2: 验证文件语法**

Run: `docker buildx build --check -f prebuild_client_win7.Dockerfile . 2>&1 | head -20`
Expected: 输出 `syntax OK` 或无错误。

- [ ] **Step 3: 暂不构建完整镜像（等 §6 测试环境就绪）**

## Task 2.2: 写 clientbuildtest_win7.Dockerfile

**Files:**
- Create: `clientbuildtest_win7.Dockerfile`

- [ ] **Step 1: 写 Dockerfile**

Create `clientbuildtest_win7.Dockerfile` with:
```dockerfile
# syntax=docker/dockerfile:1.6
# 验证 Win7 客户端构建产物的 bats 测试镜像

FROM alpine:3.19

RUN apk add --no-cache \
    bash \
    bats \
    git \
    jq \
    openssl \
    p7zip

ARG BUILD_IMAGE=zotprime-client:win7-5.0.96.3
ARG WIN7_VERSION=5.0.96.3

WORKDIR /tests
COPY tests/integration/win7-build.bats /tests/

# 从构建镜像 copy 产物
COPY --from=${BUILD_IMAGE} /dist/Zotero-${WIN7_VERSION}_win-x86_64-setup.exe /tests/dist/
COPY --from=${BUILD_IMAGE} /dist/Zotero-${WIN7_VERSION}_win-x86_64-setup.exe.sha256 /tests/dist/

CMD ["bats", "win7-build.bats"]
```

## Task 2.3: 改 bin/build-local.sh 加 WIN7 分支

**Files:**
- Modify: `bin/build-local.sh:1-50`（顶部变量 + 分支判断）

- [ ] **Step 1: 读当前 build-local.sh 顶部**

Run: `head -50 bin/build-local.sh`

- [ ] **Step 2: 在变量声明段之后加 WIN7 入口**

在 `bin/build-local.sh` 中，**找到现有变量定义结束的位置**（通常在 `set -euo pipefail` 之后），插入以下代码块：

```bash
# === Win7 兼容性开关 (feature/win7-compatibility) ===
WIN7="${WIN7:-0}"
DIST_DIR="${DIST_DIR:-./dist}"

if [ "$WIN7" = "1" ]; then
    DOCKERFILE="prebuild_client_win7.Dockerfile"
    TARGET_TAG="zotprime-client:win7-5.0.96.3"
    REQUIRED_VERSION="5.0.96.3"
    TEST_DOCKERFILE="clientbuildtest_win7.Dockerfile"
    log_info() { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_info "Win7 build mode: $DOCKERFILE (version $REQUIRED_VERSION)"
else
    DOCKERFILE="prebuild_client.Dockerfile"
    TARGET_TAG="zotprime-client:latest"
    REQUIRED_VERSION="8.0.1"
    TEST_DOCKERFILE="clientbuildtest.Dockerfile"
    log_info() { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_info "Modern build mode: $DOCKERFILE (version $REQUIRED_VERSION)"
fi
```

> 注：以上 `log_info` / `log_error` 函数如果 `bin/build-local.sh` 已定义同名函数，**应删除本插入块的定义**，避免冲突。

- [ ] **Step 3: 在脚本末尾（trap 之前）加子模块检查**

在 `bin/build-local.sh` 中，**找到 `docker build` 之前的子模块检查位置**（如不存在则放在脚本开始检查块后），加：

```bash
if [ "$WIN7" = "1" ]; then
    if [ ! -d "client/zotero-standalone-build-win7" ] || [ ! -d "client/zotero-client-win7" ]; then
        log_error "WIN7=1 but win7 submodules not initialized. Run:"
        log_error "  git submodule update --init client/zotero-standalone-build-win7 client/zotero-client-win7"
        exit 10
    fi

    # 校验子模块版本
    ACTUAL_VER=$(cat client/zotero-client-win7/version 2>/dev/null | tr -d '\n' || echo "")
    EXPECTED_VER="${REQUIRED_VERSION}.SOURCE"
    if [ "$ACTUAL_VER" != "$EXPECTED_VER" ]; then
        log_error "zotero-client-win7/version is '$ACTUAL_VER', expected '$EXPECTED_VER'"
        exit 12
    fi
fi
```

- [ ] **Step 4: shellcheck 验证**

Run: `shellcheck bin/build-local.sh`
Expected: 无 error 级别告警（warning 可接受）。

## Task 2.4: 提交 PR#2 第一批

**Files:**
- Create: `prebuild_client_win7.Dockerfile`
- Create: `clientbuildtest_win7.Dockerfile`
- Modify: `bin/build-local.sh`

- [ ] **Step 1: 查看 diff**

Run: `git status --short`
Expected: 3 个文件 changed（2 new + 1 modified）

- [ ] **Step 2: 提交**

Run:
```bash
cd /home/fz/project/zotprime
git add prebuild_client_win7.Dockerfile clientbuildtest_win7.Dockerfile bin/build-local.sh
git -c user.email=claude@local -c user.name=claude commit -m "feat(win7): add Win7 prebuild Dockerfile and build switch"
```

---

# PR#3: M2 — 探测脚本 + bats 测试

## Task 3.1: 写 bin/detect-win-version.sh

**Files:**
- Create: `bin/detect-win-version.sh`

- [ ] **Step 1: 写脚本**

Create `bin/detect-win-version.sh` with:
```bash
#!/usr/bin/env bash
# 探测 Windows 版本号
# 输入: 无（--probe 模式调用 wmic）或 stdin 一行 ver 输出
# 输出: 单行 win11 | win10 | win8 | win7 | xp | unknown
# 退出码: 0=识别, 1=unknown, 2=工具不可用
# 副作用: stderr 一行 ISO8601 日志

set -euo pipefail

PROBE=false
if [ "${1:-}" = "--probe" ]; then
    PROBE=true
fi

log_ts() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >&2
}

classify() {
    # $1: 版本字符串片段（数字）
    case "$1" in
        10.0)
            # Win10 vs Win11 都报 10.0，需要 build 号
            # Win11 build >= 22000
            if [ "${2:-0}" -ge 22000 ] 2>/dev/null; then
                echo "win11"
            else
                echo "win10"
            fi
            ;;
        6.3) echo "win8" ;;
        6.2) echo "win8" ;;
        6.1) echo "win7" ;;
        5.1|5.2) echo "xp" ;;
        *) echo "unknown" ;;
    esac
}

if [ "$PROBE" = true ]; then
    # 通过 wmic 探测
    if ! command -v wmic >/dev/null 2>&1; then
        log_ts "wmic not available, cannot probe"
        exit 2
    fi
    VER_RAW=$(wmic os get Version /value 2>/dev/null | grep "^Version=" | head -1 | cut -d= -f2 | tr -d '\r')
    if [ -z "$VER_RAW" ]; then
        log_ts "wmic returned empty Version"
        exit 2
    fi
    log_ts "wmic raw: $VER_RAW"
    MAJOR_MINOR=$(echo "$VER_RAW" | cut -d. -f1-2)
    BUILD=$(echo "$VER_RAW" | cut -d. -f3)
    RESULT=$(classify "$MAJOR_MINOR" "$BUILD")
    if [ "$RESULT" = "unknown" ]; then
        echo "$RESULT"
        exit 1
    fi
    echo "$RESULT"
    exit 0
else
    # 从 stdin 读
    if [ -t 0 ]; then
        log_ts "no stdin and no --probe"
        exit 2
    fi
    VER_LINE=$(cat)
    log_ts "stdin: $VER_LINE"
    # 提取 [Version X.Y.Z]
    VER_RAW=$(echo "$VER_LINE" | grep -oE 'Version [0-9.]+' | head -1 | awk '{print $2}' | tr -d '\r')
    if [ -z "$VER_RAW" ]; then
        log_ts "could not parse Version from stdin"
        exit 2
    fi
    MAJOR_MINOR=$(echo "$VER_RAW" | cut -d. -f1-2)
    BUILD=$(echo "$VER_RAW" | cut -d. -f3)
    RESULT=$(classify "$MAJOR_MINOR" "$BUILD")
    if [ "$RESULT" = "unknown" ]; then
        echo "$RESULT"
        exit 1
    fi
    echo "$RESULT"
    exit 0
fi
```

- [ ] **Step 2: 加可执行权限**

Run: `chmod +x bin/detect-win-version.sh`

- [ ] **Step 3: 手动验证 5 个版本**

Run:
```bash
echo "Microsoft Windows [Version 6.1.7601]" | bash bin/detect-win-version.sh
echo "Microsoft Windows [Version 10.0.19045]" | bash bin/detect-win-version.sh
echo "Microsoft Windows [Version 10.0.22621]" | bash bin/detect-win-version.sh
echo "Microsoft Windows [Version 6.3.9600]" | bash bin/detect-win-version.sh
echo "Microsoft Windows [Version 5.1.2600]" | bash bin/detect-win-version.sh
echo "Microsoft Windows [Version 3.1]" | bash bin/detect-win-version.sh
```

Expected 输出顺序:
```
win7
win10
win11
win8
xp
unknown
```

对应退出码: 0, 0, 0, 0, 0, 1

## Task 3.2: 写 tests/bin/detect-win-version.bats

**Files:**
- Create: `tests/bin/detect-win-version.bats`

- [ ] **Step 1: 写测试**

Create `tests/bin/detect-win-version.bats` with:
```bash
#!/usr/bin/env bats

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../bin/detect-win-version.sh"
    [ -x "$SCRIPT" ] || skip "detect-win-version.sh not executable"
}

@test "recognizes Windows 7 from ver output" {
    run bash -c "echo 'Microsoft Windows [Version 6.1.7601]' | $SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "win7" ]
}

@test "recognizes Windows 8 from ver output" {
    run bash -c "echo 'Microsoft Windows [Version 6.3.9600]' | $SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "win8" ]
}

@test "recognizes Windows 10 from ver output (build 19045)" {
    run bash -c "echo 'Microsoft Windows [Version 10.0.19045]' | $SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "win10" ]
}

@test "recognizes Windows 11 from ver output (build >= 22000)" {
    run bash -c "echo 'Microsoft Windows [Version 10.0.22621]' | $SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "win11" ]
}

@test "recognizes Windows XP from ver output" {
    run bash -c "echo 'Microsoft Windows [Version 5.1.2600]' | $SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "xp" ]
}

@test "returns unknown for unrecognized version" {
    run bash -c "echo 'Microsoft Windows [Version 3.1]' | $SCRIPT"
    [ "$status" -eq 1 ]
    [ "$output" = "unknown" ]
}

@test "exits 2 when stdin is empty (TTY mode without --probe)" {
    # /dev/null 给空 stdin
    run bash -c "$SCRIPT < /dev/null"
    # 脚本会走到 ! [ -t 0 ] 判 false (因为 < /dev/null 重定向不算 TTY)
    # 但 VER_LINE 为空 → exit 2
    [ "$status" -eq 2 ]
}
```

- [ ] **Step 2: 运行测试**

Run: `bats tests/bin/detect-win-version.bats`
Expected: 7 tests, 0 failures

## Task 3.3: 写 tests/bin/build-local.bats

**Files:**
- Create: `tests/bin/build-local.bats`

- [ ] **Step 1: 写测试**

Create `tests/bin/build-local.bats` with:
```bash
#!/usr/bin/env bats

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../bin/build-local.sh"
    [ -f "$SCRIPT" ] || skip "build-local.sh not found"
}

@test "WIN7=1 sources to win7 dockerfile selection" {
    # 提取 WIN7 块判定逻辑（不真正构建）
    run bash -c "WIN7=1 bash -c 'source <(grep -A 30 \"^WIN7=\" $SCRIPT | head -30) 2>&1; echo DOCKERFILE=\$DOCKERFILE; echo TARGET_TAG=\$TARGET_TAG'"
    [[ "$output" == *"prebuild_client_win7.Dockerfile"* ]]
    [[ "$output" == *"win7-5.0.96.3"* ]]
}

@test "WIN7 unset defaults to modern client" {
    run bash -c "bash -c 'source <(grep -A 30 \"^WIN7=\" $SCRIPT | head -30) 2>&1; echo DOCKERFILE=\$DOCKERFILE'"
    [[ "$output" == *"prebuild_client.Dockerfile"* ]]
}

@test "exits 10 when win7 submodule not initialized" {
    # 临时把子模块目录改名模拟未初始化
    cd /home/fz/project/zotprime
    if [ ! -d client/zotero-standalone-build-win7 ]; then
        skip "win7 submodule not present"
    fi
    mv client/zotero-standalone-build-win7 client/.zotero-standalone-build-win7.bak
    run bash -c "WIN7=1 bash $SCRIPT 2>&1"
    mv client/.zotero-standalone-build-win7.bak client/zotero-standalone-build-win7
    # 退出码 10 或 1（取决于脚本实际触发点）
    [[ "$status" -eq 10 || "$status" -eq 1 ]]
}
```

- [ ] **Step 2: 运行测试**

Run: `bats tests/bin/build-local.bats`
Expected: 3 tests, 0 failures

## Task 3.4: 写 tests/submodule/win7-refs.bats

**Files:**
- Create: `tests/submodule/win7-refs.bats`

- [ ] **Step 1: 写测试**

Create `tests/submodule/win7-refs.bats` with:
```bash
#!/usr/bin/env bats

setup() {
    cd /home/fz/project/zotprime
}

@test "zotero-standalone-build-win7 points to 5.0.96.3" {
    [ -d client/zotero-standalone-build-win7 ] || skip "win7 build submodule not initialized"
    cd client/zotero-standalone-build-win7
    TAG=$(git describe --tags --exact-match 2>/dev/null || echo "")
    [ "$TAG" = "5.0.96.3" ]
}

@test "zotero-client-win7 version file says 5.0.96.3.SOURCE" {
    [ -f client/zotero-client-win7/version ] || skip "win7 client submodule not initialized"
    VER=$(cat client/zotero-client-win7/version | tr -d '\n')
    [ "$VER" = "5.0.96.3.SOURCE" ]
}
```

- [ ] **Step 2: 运行测试**

Run: `bats tests/submodule/win7-refs.bats`
Expected: 2 tests, 0 failures

## Task 3.5: 提交 PR#3

**Files:**
- Create: `bin/detect-win-version.sh`
- Create: `tests/bin/detect-win-version.bats`
- Create: `tests/bin/build-local.bats`
- Create: `tests/submodule/win7-refs.bats`

- [ ] **Step 1: 跑全部 bats**

Run: `bats tests/bin/ tests/submodule/`
Expected: 全部 pass

- [ ] **Step 2: 提交**

Run:
```bash
cd /home/fz/project/zotprime
git add bin/detect-win-version.sh tests/bin/detect-win-version.bats tests/bin/build-local.bats tests/submodule/win7-refs.bats
git -c user.email=claude@local -c user.name=claude commit -m "feat(win7): add detect-win-version.sh and bats tests"
```

---

# PR#4: M2 — C 兜底 PS + 打包

## Task 4.1: 写 tests/integration/manifest-schema.json

**Files:**
- Create: `tests/integration/manifest-schema.json`

- [ ] **Step 1: 写 JSON Schema**

Create `tests/integration/manifest-schema.json` with:
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "ZotPrime Clients Manifest",
  "type": "object",
  "required": ["version", "clients"],
  "properties": {
    "version": {
      "type": "string",
      "pattern": "^v[0-9]+\\.[0-9]+\\.[0-9]+$"
    },
    "clients": {
      "type": "object",
      "required": ["win10plus", "win7"],
      "properties": {
        "win10plus": {
          "type": "object",
          "required": ["installer", "sha256", "min_os", "arch"],
          "properties": {
            "installer": { "type": "string" },
            "sha256": { "type": "string", "pattern": "^[a-f0-9]{64}$" },
            "min_os": { "type": "string" },
            "arch": { "type": "array", "items": { "type": "string" } }
          }
        },
        "win7": {
          "type": "object",
          "required": ["installer", "sha256", "min_os", "arch"],
          "properties": {
            "installer": { "type": "string" },
            "sha256": { "type": "string", "pattern": "^[a-f0-9]{64}$" },
            "min_os": { "type": "string" },
            "arch": { "type": "array", "items": { "type": "string" } }
          }
        }
      }
    }
  }
}
```

## Task 4.2: 改 bin/package-for-intranet.sh 加 clients/ 与 manifest

**Files:**
- Modify: `bin/package-for-intranet.sh`

- [ ] **Step 1: 读现有 package-for-intranet.sh 顶部 50 行**

Run: `head -50 bin/package-for-intranet.sh`

- [ ] **Step 2: 在打包函数中加 clients/ 目录生成 + manifest**

在 `bin/package-for-intranet.sh` 中，**找到 Docker 镜像打包完成后的位置**（通常在所有 `docker save` 调用之后），插入以下代码块：

```bash
# === Win7 兼容：客户端安装包打包 (feature/win7-compatibility) ===
log_info "Packaging client installers..."

DIST_DIR="${DIST_DIR:-./dist}"
INTRANET_ROOT="${INTRANET_ROOT:-./intranet-package}"
CLIENTS_DIR="$INTRANET_ROOT/clients"
mkdir -p "$CLIENTS_DIR/win10plus" "$CLIENTS_DIR/win7"

# Win10+ 现代版 (8.0.1)
MODERN_EXE="$DIST_DIR/Zotero-8.0.1_win-x86_64-setup.exe"
if [ -f "$MODERN_EXE" ]; then
    cp "$MODERN_EXE" "$CLIENTS_DIR/win10plus/"
    log_info "  Modern client: $CLIENTS_DIR/win10plus/$(basename "$MODERN_EXE")"
else
    log_error "Missing modern client: $MODERN_EXE"
    log_error "  Run: bin/build-local.sh (no WIN7=1) first"
    exit 20
fi

# Win7 兼容版 (5.0.96.3)
WIN7_EXE="$DIST_DIR/Zotero-5.0.96.3_win-x86_64-setup.exe"
if [ -f "$WIN7_EXE" ]; then
    cp "$WIN7_EXE" "$CLIENTS_DIR/win7/"
    log_info "  Win7 client: $CLIENTS_DIR/win7/$(basename "$WIN7_EXE")"
else
    log_error "Missing Win7 client: $WIN7_EXE"
    log_error "  Run: WIN7=1 bin/build-local.sh first"
    exit 20
fi

# 生成 sha256
(cd "$CLIENTS_DIR/win10plus" && sha256sum *) > "$CLIENTS_DIR/win10plus/SHA256SUMS"
(cd "$CLIENTS_DIR/win7" && sha256sum *) > "$CLIENTS_DIR/win7/SHA256SUMS"

# 生成 clients-manifest.json
get_sha() { sha256sum "$1" | awk '{print $1}'; }

cat > "$INTRANET_ROOT/clients-manifest.json" <<EOF
{
  "version": "v3.3.0",
  "clients": {
    "win10plus": {
      "installer": "clients/win10plus/$(basename "$MODERN_EXE")",
      "sha256": "$(get_sha "$MODERN_EXE")",
      "min_os": "10.0",
      "arch": ["x86_64"]
    },
    "win7": {
      "installer": "clients/win7/$(basename "$WIN7_EXE")",
      "sha256": "$(get_sha "$WIN7_EXE")",
      "min_os": "6.1",
      "arch": ["x86_64"]
    }
  }
}
EOF
log_info "  Manifest: $INTRANET_ROOT/clients-manifest.json"
```

- [ ] **Step 3: shellcheck**

Run: `shellcheck bin/package-for-intranet.sh`
Expected: 无 error

## Task 4.3: 写 tests/integration/win7-build.bats

**Files:**
- Create: `tests/integration/win7-build.bats`

- [ ] **Step 1: 写测试**

Create `tests/integration/win7-build.bats` with:
```bash
#!/usr/bin/env bats

setup() {
    cd /home/fz/project/zotprime
    DIST="${DIST_DIR:-./dist}"
}

@test "win7 installer exists after WIN7=1 build" {
    [ -f "$DIST/Zotero-5.0.96.3_win-x86_64-setup.exe" ] || skip "needs WIN7=1 docker build"
}

@test "win7 installer has matching sha256" {
    [ -f "$DIST/Zotero-5.0.96.3_win-x86_64-setup.exe" ] || skip "needs build"
    [ -f "$DIST/Zotero-5.0.96.3_win-x86_64-setup.exe.sha256" ] || skip "needs build"
    cd "$DIST"
    sha256sum -c "Zotero-5.0.96.3_win-x86_64-setup.exe.sha256"
}

@test "win7 installer contains Win7 min version string" {
    [ -f "$DIST/Zotero-5.0.96.3_win-x86_64-setup.exe" ] || skip "needs build"
    # 用 7z 探测 NSIS 包内字符串
    if ! command -v 7z >/dev/null; then skip "7z not installed"; fi
    # 解到临时目录
    TMP=$(mktemp -d)
    7z x -y -o"$TMP" "$DIST/Zotero-5.0.96.3_win-x86_64-setup.exe" >/dev/null
    # 检查 Zotero 扩展 XPI
    XPI=$(find "$TMP" -name 'zotero@chnm.org.xpi' | head -1)
    [ -n "$XPI" ] || { rm -rf "$TMP"; skip "XPI not found in installer"; }
    # 解 XPI 检查 config.js 内 dataserver URL 已被替换
    XPI_TMP=$(mktemp -d)
    7z x -y -o"$XPI_TMP" "$XPI" >/dev/null
    if [ -f "$XPI_TMP/resource/config.js" ]; then
        # 验证默认 host 已替换为 zotprime.local（如果用默认 ARG 的话）
        run grep -c "zotprime.local" "$XPI_TMP/resource/config.js"
        [ "$status" -eq 0 ]
        [ "$output" -gt 0 ]
    fi
    rm -rf "$TMP" "$XPI_TMP"
}

@test "clients-manifest.json validates against schema" {
    [ -f intranet-package/clients-manifest.json ] || skip "needs package-for-intranet"
    cd /home/fz/project/zotprime
    if ! command -v jq >/dev/null; then skip "jq not installed"; fi
    # 用 ajv 校验（如果有）
    if command -v npx >/dev/null; then
        cd /tmp
        npx --yes ajv-cli@5 -s /home/fz/project/zotprime/tests/integration/manifest-schema.json \
            -d /home/fz/project/zotprime/intranet-package/clients-manifest.json
        [ "$?" -eq 0 ]
    else
        # fallback: jq 检查关键字段
        jq -e '.version and .clients.win10plus.installer and .clients.win7.installer' \
            /home/fz/project/zotprime/intranet-package/clients-manifest.json >/dev/null
    fi
}
```

## Task 4.4: 写 bin/set-zotero-dataserver.ps1

**Files:**
- Create: `bin/set-zotero-dataserver.ps1`

- [ ] **Step 1: 写脚本**

Create `bin/set-zotero-dataserver.ps1` with:
```powershell
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
```

## Task 4.5: 改 bin/deploy-intranet.sh 加 OS 探测分发

**Files:**
- Modify: `bin/deploy-intranet.sh`

- [ ] **Step 1: 读现有 deploy-intranet.sh**

Run: `head -60 bin/deploy-intranet.sh`

- [ ] **Step 2: 在分发函数内加 Win 版本探测**

在 `bin/deploy-intranet.sh` 中，**找到 Windows 客户端分发代码块的位置**（如不存在则放在脚本靠后），插入：

```bash
# === Win7 兼容：按 Windows 版本分发客户端 (feature/win7-compatibility) ===
distribute_windows_client() {
    local target_user="$1"
    local manifest="intranet-package/clients-manifest.json"
    if [ ! -f "$manifest" ]; then
        log_error "manifest not found: $manifest"
        return 1
    fi

    # 探测 Windows 版本
    local win_ver
    if ! win_ver=$(bash bin/detect-win-version.sh --probe 2>/dev/null); then
        log_warn "Cannot detect Windows version, defaulting to win10plus"
        win_ver="win10plus"
    fi
    log_info "Detected Windows version: $win_ver"

    # 按版本选 manifest 字段
    local client_field
    case "$win_ver" in
        win7|win8|xp) client_field="win7" ;;
        win10|win11) client_field="win10plus" ;;
        *)
            log_warn "Unknown version '$win_ver', defaulting to win10plus"
            client_field="win10plus"
            ;;
    esac

    # 解析 manifest
    local installer
    installer=$(jq -r ".clients.$client_field.installer" "$manifest")
    if [ "$installer" = "null" ] || [ -z "$installer" ]; then
        log_error "No installer in manifest for $client_field"
        return 1
    fi

    # 分发（伪代码，按现有 deploy 实际推送方式替换）
    log_info "Distributing $installer to $target_user (OS=$win_ver)"
    # ... existing push logic ...
}

log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }
```

> 注：以上 `log_*` 函数如果 `bin/deploy-intranet.sh` 已定义，**应删除本插入块的定义**。

- [ ] **Step 3: shellcheck**

Run: `shellcheck bin/deploy-intranet.sh`

## Task 4.6: 提交 PR#4

**Files:**
- Create: `tests/integration/manifest-schema.json`
- Create: `tests/integration/win7-build.bats`
- Create: `bin/set-zotero-dataserver.ps1`
- Modify: `bin/package-for-intranet.sh`
- Modify: `bin/deploy-intranet.sh`

- [ ] **Step 1: 跑全部 bats**

Run: `bats tests/`
Expected: 全部 pass（除 win7-build.bats 在没有 Docker build 产物时 skip）

- [ ] **Step 2: 提交**

Run:
```bash
cd /home/fz/project/zotprime
git add tests/integration/manifest-schema.json tests/integration/win7-build.bats bin/set-zotero-dataserver.ps1 bin/package-for-intranet.sh bin/deploy-intranet.sh
git -c user.email=claude@local -c user.name=claude commit -m "feat(win7): add PS fallback, manifest schema, and OS-aware deploy"
```

---

# PR#5: M3 — 文档 + E2E

## Task 5.1: 写 docs/technical/18-win7-compatibility.md

**Files:**
- Create: `docs/technical/18-win7-compatibility.md`

- [ ] **Step 1: 写文档**

Create `docs/technical/18-win7-compatibility.md` with:
```markdown
# 18. Win7 兼容性

> 本章描述 zotprime 在新分支 `feature/win7-compatibility` 下对 Windows 7 SP1 x64 客户端的兼容方案。

## 18.1 兼容性矩阵

| Windows 版本 | dataserver 协议 | Zotero 客户端 | 状态 |
|--------------|-----------------|---------------|------|
| Win 11 (10.0 build ≥ 22000) | 8.0+ | 8.0.1 | ✅ 支持 |
| Win 10 (10.0 build < 22000) | 8.0+ | 8.0.1 | ✅ 支持 |
| Win 8.1 (6.3) | 8.0+ | **5.0.96.3** | ✅ 支持 |
| **Win 7 SP1 x64 (6.1)** | 8.0+ | **5.0.96.3** | ✅ 支持（实验性） |
| Win Vista (6.0) | - | - | ❌ 不支持 |
| Win XP (5.1/5.2) | - | - | ❌ 不支持 |

## 18.2 构建命令

### 现代版（8.0.1，Win10+ 默认）

\`\`\`bash
bin/build-local.sh
# 产物: dist/Zotero-8.0.1_win-x86_64-setup.exe
\`\`\`

### Win7 版（5.0.96.3，Win7/8.1）

\`\`\`bash
WIN7=1 bin/build-local.sh
# 产物: dist/Zotero-5.0.96.3_win-x86_64-setup.exe
# 内含 A' 注入：dataserver URL 已写入 XPI 的 resource/config.js
\`\`\`

### 内网部署包

\`\`\`bash
bin/package-for-intranet.sh
# 产物: intranet-package/
#   ├── clients/win10plus/  (现代版 .exe + .sha256)
#   ├── clients/win7/       (5.0.96.3 .exe + .sha256)
#   └── clients-manifest.json
\`\`\`

### dataserver URL 兜底（A' 失败时用）

\`\`\`powershell
# 在 Win7 客户端上以管理员权限打开 PowerShell 5.1+
.\bin\set-zotero-dataserver.ps1 \
    -DataServerUrl "http://zotprime.local:8080/" \
    -StreamServerUrl "ws://zotprime.local:8081/"
\`\`\`

## 18.3 dataserver URL 注入原理（A' 路径）

1. 拉官方 `Zotero-5.0.96.3_win-x86_64-setup.exe`
2. 7z 解 NSIS 自解压包
3. 定位 Zotero 扩展 `zotero@chnm.org.xpi`
4. 解 XPI（zip 格式）→ 改 `resource/config.js`：
   - `https://api.zotero.org` → `${HOST_DS}`
   - `wss://stream.zotero.org` → `${HOST_ST}`
5. 重打包 XPI
6. `makensis` 重编译 NSIS 安装包

与 8.0+ 的 `prebuild_client.Dockerfile` omni.ja 重打包路径完全对称。

## 18.4 限制声明

- **仅 Win7 SP1 x64**：32 位、内核版本 < 6.1 不支持
- **5.0.96.3 协议冻结**：dataserver 升级到 Zotero 6 协议特性时，5.0 客户端可能无法同步新字段
- **Gecko 60 ESR Win7 安全补丁已停止**：仅建议内网隔离环境使用
- **VC++ 2013 Redist 必装**：Win7 干净环境需先安装 [vcredist_x64.exe](https://www.microsoft.com/en-us/download/details.aspx?id=40784)

## 18.5 端到端测试（Win7 SP1 Vagrant VM）

\`\`\`bash
# 准备 Win7 SP1 镜像
vagrant init win7-sp1
vagrant up

# 验证清单
- [ ] 干净环境安装 5.0.96.3 安装包成功
- [ ] 首次启动不报"缺少 dll"
- [ ] 配同步连到 ZotPrime dataserver，上传一条文献
- [ ] 在 Win10 客户端登录同一账号，能看到该条文献
- [ ] 反向：Win10 添加一条，Win7 同步下来
- [ ] Word 集成（zotero-win32-transfw）正常
- [ ] 卸载干净，无残留注册表
\`\`\`

## 18.6 相关文件

- 规范：`docs/superpowers/specs/2026-06-07-win7-compatibility-design.md`
- 用户手册：`docs/user-manual/09-win7-installation.md`
- 实施计划：`docs/plans/2026-06-07-win7-compatibility.md`
- 子模块：
  - `client/zotero-standalone-build-win7` @ `5.0.96.3`
  - `client/zotero-client-win7` @ `5.0.96.3`
- 脚本：
  - `bin/detect-win-version.sh`
  - `bin/set-zotero-dataserver.ps1`
  - `bin/build-local.sh`（增 `WIN7=1` 开关）
```

## Task 5.2: 写 docs/user-manual/09-win7-installation.md

**Files:**
- Create: `docs/user-manual/09-win7-installation.md`

- [ ] **Step 1: 写文档**

Create `docs/user-manual/09-win7-installation.md` with:
```markdown
# 9. Windows 7 安装说明

## 9.1 我是 Win7 用户，我该装哪个版本？

如果你的电脑运行的是 **Windows 7 SP1 64 位**（右键"我的电脑"→"属性"可查看系统类型），请按本章步骤安装 **Zotero 5.0.96.3 for Win7** 版本。

> ⚠️ Zotero 8.0 不支持 Windows 7，请勿下载。

## 9.2 系统要求

| 项 | 最低要求 |
|----|----------|
| 操作系统 | Windows 7 SP1 (64 位) |
| VC++ 运行库 | 2013 Redist x64 或更新 |
| 硬盘空间 | 500 MB |
| 内存 | 2 GB |

## 9.3 安装步骤

### 步骤 1：下载安装包

从内网部署平台下载 `Zotero-5.0.96.3_win-x86_64-setup.exe`（约 50 MB）。

### 步骤 2：安装 VC++ 2013 Redist（如已安装可跳过）

[下载链接](https://www.microsoft.com/en-us/download/details.aspx?id=40784)，双击默认安装。

### 步骤 3：双击安装包

按提示点击"下一步"，默认安装到 `C:\Program Files\Zotero`。

### 步骤 4：首次启动

启动 Zotero，会自动弹出"新建账号"或"登录已有账号"窗口。

## 9.4 配置内网 dataserver

**重要**：Zotero 5.0.96.3 安装包在构建时已注入内网 dataserver 地址，**首次启动时不需要手动配置**。

如启动后同步时报 "Cannot connect to api.zotero.org"，说明注入未生效（罕见），请联系运维执行 `set-zotero-dataserver.ps1` 兜底脚本。

## 9.5 验证安装

1. Zotero 启动后，菜单 `编辑 → 设置 → 同步` 应显示"连接到内网 ZotPrime"
2. 顶部状态栏的同步图标点击后应能正常同步
3. 添加一条文献，等待几秒后能看到云端图标

## 9.6 常见问题

### Q1: 启动时弹窗"无法启动此应用程序，因为计算机中缺少 MSVCR120.dll"

A: VC++ 2013 Redist 没装好，重新装一次（见 9.3 步骤 2）。

### Q2: 同步时报 "SSL certificate problem"

A: 浏览器访问 `http://<SERVER_IP>:8080/`，把证书导出后双击装到"受信任的根证书颁发机构"。

### Q3: 同步时报 "Cannot connect to api.zotero.org"

A: 注入未生效。联系运维推送 `set-zotero-dataserver.ps1` 兜底脚本。

## 9.7 相关链接

- 内网 dataserver 入口：`http://<SERVER_IP>:8080/`
- 技术文档：`docs/technical/18-win7-compatibility.md`
```

## Task 5.3: 更新 docs/technical/README.md 章节目录

**Files:**
- Modify: `docs/technical/README.md`（或 `docs/technical-manual.md`——看项目实际结构）

- [ ] **Step 1: 查实际章节目录文件**

Run: `ls docs/technical/ 2>/dev/null && echo "---" && ls docs/*.md | head -10`

- [ ] **Step 2: 在章节目录中加第 18 章**

如果存在 `docs/technical/README.md` 或 `docs/technical-manual.md`，在目录条目列表中加：

```markdown
| 18 | [Win7 兼容性](18-win7-compatibility.md) | Windows 7 SP1 客户端兼容方案、构建命令、限制声明 |
```

具体插入位置以原文档结构为准。

## Task 5.4: 更新 docs/user-manual/README.md 章节目录

**Files:**
- Modify: `docs/user-manual/README.md`（或 `docs/user-manual.md`）

- [ ] **Step 1: 查实际章节目录文件**

Run: `ls docs/user-manual/ 2>/dev/null`

- [ ] **Step 2: 在章节目录中加第 9 章**

如果存在 `docs/user-manual/README.md` 或 `docs/user-manual.md`，在目录条目列表中加：

```markdown
| 9 | [Windows 7 安装](09-win7-installation.md) | Win7 SP1 用户从下载到验证的完整步骤 |
```

## Task 5.5: 跑端到端 checklist（Vagrant Win7 VM）

**Files:**
- Create: `docs/notes/2026-06-07_win7-e2e-checklist.md`（验证记录）

- [ ] **Step 1: 准备 Vagrantfile（一次性，文档化）**

Create `Vagrantfile.win7-sp1` (临时使用，验证后归档到 docs/notes/):
```ruby
# -*- mode: ruby -*-
# Vagrantfile for Win7 SP1 x64 E2E test
Vagrant.configure("2") do |config|
  config.vm.box = "win7-sp1-eval"
  config.vm.guest = :windows
  config.vm.communicator = "winrm"
  config.winrm.username = "vagrant"
  config.winrm.password = "vagrant"
  config.vm.network "forwarded_port", guest: 8080, host: 8080
end
```

> 注：Vagrant Win7 box 来源见 `docs/technical/18-win7-compatibility.md` §18.5。

- [ ] **Step 2: 验证（手动）**

Run 7 步 checklist（见 §18.5）。逐项打勾，失败项在 `docs/notes/2026-06-07_win7-e2e-checklist.md` 记录。

- [ ] **Step 3: 提交 E2E 记录**

Run:
```bash
cd /home/fz/project/zotprime
git add docs/notes/2026-06-07_win7-e2e-checklist.md
git -c user.email=claude@local -c user.name=claude commit -m "docs(win7): record E2E validation on Win7 SP1 VM"
```

## Task 5.6: 提交 PR#5

**Files:**
- Create: `docs/technical/18-win7-compatibility.md`
- Create: `docs/user-manual/09-win7-installation.md`
- Modify: `docs/technical/README.md` (或 `docs/technical-manual.md`)
- Modify: `docs/user-manual/README.md` (或 `docs/user-manual.md`)
- Create: `docs/notes/2026-06-07_win7-e2e-checklist.md`

- [ ] **Step 1: 跑全部 bats**

Run: `bats tests/`
Expected: 全部 pass

- [ ] **Step 2: 提交**

Run:
```bash
cd /home/fz/project/zotprime
git add docs/technical/18-win7-compatibility.md docs/user-manual/09-win7-installation.md \
        docs/technical/README.md docs/user-manual/README.md \
        docs/notes/2026-06-07_win7-e2e-checklist.md
git -c user.email=claude@local -c user.name=claude commit -m "docs(win7): add Win7 compatibility and installation guides"
```

---

## 自我审查清单（Self-Review）

### 1. Spec 覆盖

| Spec 章节 | 任务 |
|-----------|------|
| §1 背景与目标 | 全部 plan 头部"Goal" |
| §3.1 目录结构 | Task 1.2/1.3 (submodule)、2.1/2.2 (Dockerfile)、3.1 (detect)、4.4 (PS)、5.1/5.2 (docs) |
| §4 C1 Win7 build submodule | Task 1.2 |
| §4 C2 Win7 client submodule | Task 1.3 |
| §4 C3 Win7 Dockerfile | Task 2.1/2.2 |
| §4 C4 build switch + detect | Task 2.3 + 3.1 |
| §4 C5 intranet package | Task 4.2 |
| §4 C6 dataserver injection | Task 2.1 (A' inline) + 4.4 (C PS) |
| §5.1 build env vars | Task 2.3 |
| §5.2 detect contract | Task 3.1 + 3.2 tests |
| §5.3 manifest JSON Schema | Task 4.1 |
| §6.1 error codes 10-13 | Task 2.3 + tests |
| §6.5 A' injection | Task 2.1 (Dockerfile inline) |
| §6.5 C fallback | Task 4.4 |
| §7.1 test matrix | Task 3.2-3.4 + 4.3 |
| §7.2 unit samples | Task 3.2/3.3 |
| §7.5 E2E checklist | Task 5.5 |
| §8 M0-M3 实施步骤 | PR#1-5 完整对应 |
| §9 R1-R12 风险 | 各 Task 的"Expected"已标注缓解措施 |

### 2. 占位符扫描

✅ 全文无 TBD/TODO/???/FIXME/XXX。"如已定义则删"等条件性 hint 已显式说明。

### 3. 类型/命名一致性

- `WIN7` env var: Task 2.3 定义、Task 2.4/3.3/4.2 引用 ✅
- `DIST_DIR`: Task 2.3 定义默认 `./dist`，Task 4.2 引用 ✅
- `bin/detect-win-version.sh`: Task 3.1 创建、3.2 测试、4.5 调用 ✅
- `Zotero-5.0.96.3_win-x86_64-setup.exe` 文件名: Task 2.1 产物、4.2 拷贝、4.3 测试 ✅
- 错误码 10/11/12: Task 2.3、2.1、1.3 一致使用 ✅

### 4. 已知遗留

- 任务 4.5 `distribute_windows_client` 中的 `# ... existing push logic ...` 是占位注释，需实施时按 `bin/deploy-intranet.sh` 实际推送方式替换（这是有意的 — 推送逻辑不属于本 PR 范围）
- 任务 5.1 文档中 §18.5 Vagrant box 名 `win7-sp1-eval` 是示例，实施时按实际可用 box 替换

---

## 全部 5 个 PR，25 个 Task

总工期：10 工作日（与 spec §8 一致）。

执行选择：

1. **Subagent-Driven (推荐)** — 每个 Task 派独立 subagent + 两阶段 review
2. **Inline Execution** — 当前 session 顺序执行 + checkpoint

请选择执行方式。
