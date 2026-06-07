# syntax=docker/dockerfile:1.6
# Win7 客户端预构建：拉 5.0.96.3 setup.exe → A' 注入 → 重打包
# 用法: docker build -f prebuild_client_win7.Dockerfile \
#           --build-arg HOST_DS=http://your-host:8080/ \
#           --build-arg HOST_ST=ws://your-host:8081/ \
#           -t zotprime-client:win7-5.0.96.3 .

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
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# 1. 拉官方 5.0.96.3 Windows setup.exe
# 注: 5.0 时代官方安装包名为 Zotero-${VERSION}_setup.exe (无 _win-x86_64 后缀)
#     8.0+ 才有 _win-x86_64 后缀
RUN curl -L --fail-with-body -o /tmp/zotero-setup.exe \
    "https://download.zotero.org/client/release/5.0.96.3/Zotero-${WIN7_VERSION}_setup.exe" \
    || { echo "[FATAL] Failed to download 5.0.96.3 setup.exe" >&2; exit 11; }

# 2. 7z 解 NSIS 自解压包
RUN 7z x -y -o/opt/zotero_build /tmp/zotero-setup.exe \
    || { echo "[FATAL] 7z failed to extract NSIS package" >&2; exit 11; }

# 3. 定位 Zotero 扩展 XPI（多路径候选，适配 5.0 时代不同安装布局）
RUN echo "=== ls -la /opt/zotero_build ===" \
    && ls -la /opt/zotero_build 2>&1 | head -30 \
    && echo "=== find all files in /opt/zotero_build ===" \
    && find /opt/zotero_build -type f 2>&1 | head -30 \
    && echo "=== 寻找 XPI ===" \
    && ZOTERO_XPI=$(find /opt/zotero_build -name 'zotero@chnm.org.xpi' 2>/dev/null | head -1) \
    && if [ -z "$ZOTERO_XPI" ]; then \
         echo "[INFO] zotero@chnm.org.xpi 未找到, 查找所有 .xpi 文件:" >&2; \
         find /opt/zotero_build -name '*.xpi' 2>/dev/null | head -20 >&2; \
         echo "[INFO] 查找 extensions 目录:" >&2; \
         find /opt/zotero_build -path '*/extensions/*' 2>/dev/null | head -20 >&2; \
         echo "[FATAL] 找不到 zotero@chnm.org.xpi" >&2; exit 12; \
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
    && if [ -z "$MAIN_NSI" ]; then \
         echo "[FATAL] No .nsi installer script found in /opt/zotero_build" >&2; exit 13; \
       fi \
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
