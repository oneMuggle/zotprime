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
