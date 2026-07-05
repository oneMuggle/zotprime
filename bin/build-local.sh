#!/bin/bash
# Build all ZotPrime Docker images locally for use with docker-compose.yml.
# Images are tagged to match the docker-compose.yml image references.
#
# Usage:
#   ./bin/build-local.sh                                # build with default tag v3.2.0
#   IMAGE_TAG=my-custom ./bin/build-local.sh            # build with custom tag
#   HOST_DS=http://10.0.0.5:8080/ ./bin/build-local.sh  # inject dataserver URL (Win10+)
#   WIN7=1 ./bin/build-local.sh                         # build Win7 5.0.96.3 client

set -e

VER="${IMAGE_TAG:-v3.2.0}"
PREFIX="uniuu/zotprime"

# === Win7 兼容性开关 (feature/win7-compatibility) ===
WIN7="${WIN7:-0}"
DIST_DIR="${DIST_DIR:-./dist}"

# === 客户端 dataserver URL 注入 (Win10+ 8.0.1) ===
# 默认从 .env 读 SERVER_IP,缺省 127.0.0.1 (本地测试用)
# 重要: 这是构建期注入,改 IP 需重新 build EXE
# Win7 5.0.96.3 不在此注入 (setup.exe 是骨架,URL 由 PowerShell C 路径注入)
if [ -f .env ]; then
    ENV_SERVER_IP=$(grep -E '^SERVER_IP=' .env | head -1 | sed -E 's/^SERVER_IP=//; s/^["'\'']//; s/["'\'']$//')
fi
SERVER_IP="${SERVER_IP:-${ENV_SERVER_IP:-127.0.0.1}}"
HOST_DS="${HOST_DS:-http://${SERVER_IP}:8080/}"
HOST_ST="${HOST_ST:-ws://${SERVER_IP}:8081/}"

log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }

if [ "$WIN7" = "1" ]; then
    DOCKERFILE="prebuild_client_win7.Dockerfile"
    TARGET_TAG="zotprime-client:win7-5.0.96.3"
    REQUIRED_VERSION="5.0.96.3"
    TEST_DOCKERFILE="clientbuildtest_win7.Dockerfile"
    log_info "Win7 build mode: $DOCKERFILE (version $REQUIRED_VERSION)"

    # 子模块检查：5.0.96.3 时代没有 version 文件，从 install.rdf 提取
    if [ ! -d "client/zotero-standalone-build-win7" ] || [ ! -d "client/zotero-client-win7" ]; then
        log_error "WIN7=1 but win7 submodules not initialized. Run:"
        log_error "  git submodule update --init client/zotero-standalone-build-win7 client/zotero-client-win7"
        exit 10
    fi

    # 校验 client 子模块版本
    # 5.0.96.3 时代没有 version 文件（c55ef8714 之后才加），fallback 用 install.rdf
    # NOTE: 5.0.96.3 这个特定版本上，`version` 文件永远为空，因此 install.rdf
    # 这条分支是今天唯一会被执行的路径；保留 version 文件检查是为了将来子模块
    # 升级后仍能直接工作。
    ACTUAL_VER=$(cat client/zotero-client-win7/version 2>/dev/null | tr -d '\n' || echo "")
    EXPECTED_VER="${REQUIRED_VERSION}.SOURCE"
    if [ "$ACTUAL_VER" != "$EXPECTED_VER" ]; then
        ACTUAL_VER=$(git -C client/zotero-client-win7 show 5.0.96.3:install.rdf 2>/dev/null \
            | grep -oE 'em:version>[^<]+' | sed 's/em:version>//' | tr -d '\n' || echo "")
        if [ "$ACTUAL_VER" != "$EXPECTED_VER" ]; then
            log_error "zotero-client-win7 version is '$ACTUAL_VER', expected '$EXPECTED_VER'"
            log_error "  (checked both version file and install.rdf)"
            exit 12
        fi
    fi
else
    DOCKERFILE="prebuild_client.Dockerfile"
    TARGET_TAG="zotprime-client:latest"
    REQUIRED_VERSION="8.0.1"
    TEST_DOCKERFILE="clientbuildtest.Dockerfile"
    log_info "Modern build mode: $DOCKERFILE (version $REQUIRED_VERSION)"
fi

# TODO(win7): DOCKERFILE/TARGET_TAG/TEST_DOCKERFILE/DIST_DIR are computed above
# (in both the WIN7=1 and WIN7=0 branches) but the `docker build` invocation
# that consumes them is not in this script's current scope. The script only
# builds the server-side images (dataserver, db, elasticsearch, ...). See plan
# PR#5 follow-up. (Pre-existing issue: the WIN7=0 branch has the same gap.)

echo "Building ZotPrime images (tag: ${VER})..."

cd "$(dirname "$0")/../stack"

echo "[1/13] dataserver"
DOCKER_BUILDKIT=1 docker build -f dataserver/ds.Dockerfile -t ${PREFIX}-dataserver:${VER} dataserver/

echo "[2/13] db"
DOCKER_BUILDKIT=1 docker build -f db/db.Dockerfile -t ${PREFIX}-db:${VER} db/

echo "[3/13] elasticsearch"
DOCKER_BUILDKIT=1 docker build -f elasticsearch/es.Dockerfile -t ${PREFIX}-elasticsearch:${VER} elasticsearch/

echo "[4/13] redis"
DOCKER_BUILDKIT=1 docker build -f redis/r.Dockerfile -t ${PREFIX}-redis:${VER} redis/

echo "[5/13] memcached"
DOCKER_BUILDKIT=1 docker build -f memcached/m.Dockerfile -t ${PREFIX}-memcached:${VER} memcached/

echo "[6/13] minio"
DOCKER_BUILDKIT=1 docker build -f minio/minio.Dockerfile -t ${PREFIX}-minio:${VER} minio/

echo "[7/13] miniomc"
DOCKER_BUILDKIT=1 docker build -f minio/miniomc.Dockerfile -t ${PREFIX}-miniomc:${VER} minio/

echo "[8/13] localstack"
DOCKER_BUILDKIT=1 docker build -f localstack/ls.Dockerfile -t ${PREFIX}-localstack:${VER} localstack/

echo "[9/13] tinymceclean"
DOCKER_BUILDKIT=1 docker build -f tinymce-clean-server/tmcs.Dockerfile -t ${PREFIX}-tinymceclean:${VER} tinymce-clean-server/

echo "[10/13] streamserver"
DOCKER_BUILDKIT=1 docker build -f stream-server/sts.Dockerfile -t ${PREFIX}-streamserver:${VER} stream-server/

echo "[11/13] phpmyadmin"
DOCKER_BUILDKIT=1 docker build -f phpmyadmin/pa.Dockerfile -t ${PREFIX}-phpmyadmin:${VER} phpmyadmin/

echo "[12/13] admin"
DOCKER_BUILDKIT=1 docker build -f admin/admin.Dockerfile -t ${PREFIX}-admin:${VER} admin/

echo "[13/13] portal"
DOCKER_BUILDKIT=1 docker build -f webui/webui.Dockerfile -t ${PREFIX}-portal:${VER} webui/

# === 客户端构建 (Phase 3 PR#3) ===
cd "$(dirname "$0")/.."  # 回到项目根 (prebuild_client*.Dockerfile 在此)
mkdir -p "${DIST_DIR}"

if [ "$WIN7" = "1" ]; then
    # === Win7 5.0.96.3 客户端 ===
    # 不在 Docker 内做 A' XPI 注入 (setup.exe 是骨架)
    # URL 由 PowerShell C 路径在用户机器上注入 (bin/set-zotero-dataserver.ps1)
    echo "[14/14] client (Win7 5.0.96.3, A' deferred → PowerShell C path)"
    DOCKER_BUILDKIT=1 docker build -f prebuild_client_win7.Dockerfile -t zotprime-client:win7-5.0.96.3 .
    WIN7_OUT="${DIST_DIR}/win7"
    rm -rf "${WIN7_OUT}"
    mkdir -p "${WIN7_OUT}"
    WIN7_CONTAINER=$(docker create --name zp-client-win7 zotprime-client:win7-5.0.96.3)
    docker cp "${WIN7_CONTAINER}:/dist/." "${WIN7_OUT}/"
    docker rm -f "${WIN7_CONTAINER}" >/dev/null
    log_info "  Win7 client EXE: ${WIN7_OUT}/Zotero-5.0.96.3_win-x86_64-setup.exe"
    log_info "  ⚠ Win7 用户装机后需运行 PowerShell 注入 dataserver URL:"
    log_info "    bin/set-zotero-dataserver.ps1 -DataServerUrl '$HOST_DS' -StreamServerUrl '$HOST_ST'"
else
    # === Win10+ 8.0.1 客户端 (构建期注入 dataserver URL) ===
    # 使用 client.Dockerfile (3-stage: 改 config.mjs → npm build → dir_build -p w)
    # 产出真正的 Windows EXE 在 app/staging/
    echo "[14/14] client (Win10+ 8.0.1, build-time URL injection)"
    log_info "  Injecting HOST_DS=$HOST_DS"
    log_info "  Injecting HOST_ST=$HOST_ST"
    WIN10_OUT="${DIST_DIR}/win10plus"
    rm -rf "${WIN10_OUT}"
    mkdir -p "${WIN10_OUT}"

    # 注: client.Dockerfile 用 ARGs HOST_DS/HOST_ST (默认 localhost)
    # 我们通过 --build-arg 覆盖
    DOCKER_BUILDKIT=1 docker buildx build \
        --build-arg HOST_DS="$HOST_DS" \
        --build-arg HOST_ST="$HOST_ST" \
        --build-arg MLW=w \
        --output "type=local,dest=${WIN10_OUT}" \
        --target export-stage \
        -f client.Dockerfile .
    log_info "  Win10+ client EXE: ${WIN10_OUT}/Zotero-8.0.1_win-x86_64-setup.exe"
    log_info "  (full build, ~10-20 min)"
fi

echo ""
echo "All images built. Start with: docker compose up -d"
echo "View images: docker images | grep zotprime"
