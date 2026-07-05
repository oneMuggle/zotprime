# syntax=docker/dockerfile:1.6
# Win7 客户端预构建：拉 5.0.96.3 setup.exe → 验证 → 重新打包为统一产物
#
# 简化决策 (2026-06-07): 5.0.96.3 官方 setup.exe 是"骨架"（只含 Mozilla
# runtime + OpenOffice 集成），主 Zotero XPI 扩展 (`zotero@zotero.org`)
# 不在 setup.exe 内。spec 中描述的 A' "解 setup.exe → 改 XPI" 路径在 5.0
# 时代不可行 —— 主 XPI 必须从 client/zotero-client-win7 仓库 build_xpi
# 后再注入。
#
# 当前策略:
# 1. 拉官方 5.0.96.3 setup.exe
# 2. 7z 解 NSIS → 验证内部结构 (core/ 含 runtime + OpenOffice 集成)
# 3. **不**在 Docker 内做 A' XPI 注入
# 4. 重新打包 setup.exe 输出
# 5. 客户端安装后由 `bin/set-zotero-dataserver.ps1` (C 路径) 做 dataserver
#    URL 注入 —— A' 注入能力由 C 路径 PowerShell 在用户机器上完成

FROM debian:bookworm-slim AS base

ARG WIN7_VERSION=5.0.96.3

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    p7zip-full \
    unzip \
    zip \
    && rm -rf /var/lib/apt/lists/*

# Need a CMD so `docker create` can produce a container (used to extract /dist/)
CMD ["/bin/sh", "-c", "while true; do sleep 3600; done"]

WORKDIR /build

# 1. 拉官方 5.0.96.3 Windows setup.exe
# 注: 5.0 时代官方安装包名为 Zotero-${VERSION}_setup.exe (无 _win-x86_64 后缀)
#     8.0+ 才有 _win-x86_64 后缀
# 用 bash 不用 sh (Debian 镜像默认 sh=dash, 不支持 set -o pipefail)
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl -L --fail-with-body -o /tmp/zotero-setup.exe \
    "https://download.zotero.org/client/release/5.0.96.3/Zotero-${WIN7_VERSION}_setup.exe" \
    || { echo "[FATAL] Failed to download 5.0.96.3 setup.exe" >&2; exit 11; }

# 2. 7z 解 NSIS 自解压包
RUN 7z x -y -o/opt/zotero_build /tmp/zotero-setup.exe \
    || { echo "[FATAL] 7z failed to extract NSIS package" >&2; exit 11; }

# 3. 验证 5.0.96.3 setup.exe 内部结构
#    预期: core/ 目录存在 (含 Mozilla runtime + OpenOffice 集成)
#    注: 5.0 时代主 Zotero XPI (`zotero@zotero.org`) 不在 setup.exe 内,
#        必须从 zotero-client-win7 build 后注入 (C 路径 PowerShell 兜底)
RUN set -euo pipefail \
    && if [ ! -d /opt/zotero_build/core ]; then \
         echo "[FATAL] /opt/zotero_build/core not found — unexpected 5.0.96.3 layout" >&2; \
         echo "=== Top-level structure ===" >&2; \
         ls -la /opt/zotero_build >&2; \
         exit 12; \
       fi \
    && CORE_FILE_COUNT=$(find /opt/zotero_build/core -type f | wc -l) \
    && echo "[OK] core/ contains $CORE_FILE_COUNT files (Mozilla runtime + extensions)" \
    && if [ ! -d /opt/zotero_build/core/extensions/zoteroOpenOfficeIntegration@zotero.org ]; then \
         echo "[FATAL] OpenOffice integration extension not found" >&2; \
         exit 12; \
       fi \
    && echo "[OK] OpenOffice integration extension present" \
    && echo "[INFO] 5.0.96.3 main Zotero XPI will be injected by PowerShell (C path) at install time"

# 4. 重新打包 setup.exe (保留 Mozilla runtime, A' XPI 注入由 C 路径在安装后做)
RUN set -euo pipefail \
    && mkdir -p /dist \
    && cp /tmp/zotero-setup.exe "/dist/Zotero-${WIN7_VERSION}_win-x86_64-setup.exe" \
    && (cd /dist && sha256sum "Zotero-${WIN7_VERSION}_win-x86_64-setup.exe" \
        > "Zotero-${WIN7_VERSION}_win-x86_64-setup.exe.sha256") \
    && echo "[OK] Build complete: /dist/Zotero-${WIN7_VERSION}_win-x86_64-setup.exe" \
    && ls -la /dist/
# NOTE: We do not use a `FROM scratch AS artifact` stage. CI extracts /dist/
# via `docker create + docker cp` from the base image, which requires a
# working /bin/sh and CMD (scratch has neither).
