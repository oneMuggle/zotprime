#!/bin/bash
# Build all ZotPrime Docker images locally for use with docker-compose.yml.
# Images are tagged to match the docker-compose.yml image references.
#
# Usage:
#   ./bin/build-local.sh                          # build with default tag v3.2.0
#   IMAGE_TAG=my-custom ./bin/build-local.sh      # build with custom tag

set -e

VER="${IMAGE_TAG:-v3.2.0}"
PREFIX="uniuu/zotprime"

# === Win7 兼容性开关 (feature/win7-compatibility) ===
WIN7="${WIN7:-0}"
DIST_DIR="${DIST_DIR:-./dist}"

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

echo ""
echo "All images built. Start with: docker compose up -d"
echo "View images: docker images | grep zotprime"
