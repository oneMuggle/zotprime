#!/bin/bash
# 内网部署包打包脚本
# 在能上网的机器上运行，生成完整的离线部署包
#
# Usage:
#   ./bin/package-for-intranet.sh
#   IMAGE_TAG=v3.3.0 ./bin/package-for-intranet.sh
#
# 输出: build/zotprime-intranet-<version>.tar.gz

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

VER="${IMAGE_TAG:-v3.2.0}"
BUILD_DIR="$PROJECT_DIR/build"
PACKAGE_NAME="zotprime-intranet-${VER}"
PACKAGE_DIR="$BUILD_DIR/$PACKAGE_NAME"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

echo ""
echo "=========================================="
echo "  ZotPrime 内网部署包打包工具"
echo "  版本: ${VER}"
echo "=========================================="
echo ""

# 1. 检查 Docker
log_step "1/6 检查 Docker..."
if ! command -v docker &> /dev/null; then
    log_error "Docker 未安装，请先安装 Docker"
    exit 1
fi
if ! docker compose version &> /dev/null; then
    log_error "Docker Compose 插件未安装"
    exit 1
fi
log_info "Docker $(docker --version) 已就绪"

# 2. 检查子模块
log_step "2/6 检查 Git 子模块..."
missing_submodules=()
while IFS= read -r line; do
    if [[ "$line" == -* ]]; then
        path=$(echo "$line" | awk '{print $2}')
        missing_submodules+=("$path")
    fi
done < <(git submodule status 2>/dev/null || true)

if [ ${#missing_submodules[@]} -gt 0 ]; then
    log_warn "发现 ${#missing_submodules[@]} 个子模块未初始化，正在拉取..."
    git submodule update --init --recursive
    log_info "子模块已初始化"
else
    log_info "所有子模块已就绪"
fi

# 3. 构建镜像
log_step "3/6 构建 Docker 镜像..."
chmod +x bin/build-local.sh
bin/build-local.sh
log_info "所有镜像构建完成"

# 4. 创建打包目录并导出镜像
log_step "4/6 导出 Docker 镜像..."
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR/images"

services=(
    "dataserver:uniuu/zotprime-dataserver"
    "db:uniuu/zotprime-db"
    "elasticsearch:uniuu/zotprime-elasticsearch"
    "redis:uniuu/zotprime-redis"
    "memcached:uniuu/zotprime-memcached"
    "minio:uniuu/zotprime-minio"
    "miniomc:uniuu/zotprime-miniomc"
    "localstack:uniuu/zotprime-localstack"
    "tinymceclean:uniuu/zotprime-tinymceclean"
    "streamserver:uniuu/zotprime-streamserver"
    "phpmyadmin:uniuu/zotprime-phpmyadmin"
    "admin:uniuu/zotprime-admin"
    "portal:uniuu/zotprime-portal"
)

for entry in "${services[@]}"; do
    IFS=':' read -r short_name image <<< "$entry"
    tag="${image}:${VER}"
    if docker image inspect "$tag" &>/dev/null; then
        log_info "导出 ${short_name}..."
        docker save "$tag" -o "$PACKAGE_DIR/images/${short_name}.tar"
    else
        log_warn "镜像 $tag 不存在，跳过"
    fi
done

log_info "镜像导出完成"
du -sh "$PACKAGE_DIR/images/" | awk '{print "  镜像总大小: " $1}'

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
  "version": "${VER}",
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

# 5. 复制项目文件
log_step "5/6 复制项目文件..."
rsync -a \
    --exclude='.git' \
    --exclude='build' \
    --exclude='node_modules' \
    --exclude='vendor' \
    --exclude='__pycache__' \
    --exclude='.env' \
    --exclude='.DS_Store' \
    --exclude='*.log' \
    "$PROJECT_DIR/" "$PACKAGE_DIR/"

# 创建镜像加载脚本
cat > "$PACKAGE_DIR/load-images.sh" << 'LOAD_EOF'
#!/bin/bash
# 导入所有 Docker 镜像（在内网服务器上运行）
set -e

IMAGE_DIR="$(cd "$(dirname "$0")" && pwd)/images"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "=========================================="
echo "  ZotPrime 镜像导入"
echo "=========================================="
echo ""

if ! command -v docker &> /dev/null; then
    echo -e "${RED}[错误]${NC} Docker 未安装"
    exit 1
fi

if [ ! -d "$IMAGE_DIR" ]; then
    echo -e "${RED}[错误]${NC} images/ 目录不存在"
    exit 1
fi

count=0
total=$(ls "$IMAGE_DIR"/*.tar 2>/dev/null | wc -l)

echo "找到 $total 个镜像文件，开始导入..."
echo ""

for img in "$IMAGE_DIR"/*.tar; do
    name=$(basename "$img" .tar)
    echo -e "${GREEN}[导入]${NC} $name"
    docker load -i "$img"
    count=$((count + 1))
done

echo ""
echo "=========================================="
echo "  导入完成！$count/$total 个镜像已加载"
echo "=========================================="
echo ""
echo "验证: docker images | grep zotprime"
echo ""
LOAD_EOF

chmod +x "$PACKAGE_DIR/load-images.sh"

# 创建内网部署说明
cat > "$PACKAGE_DIR/内网部署说明.md" << 'DEPLOY_EOF'
# ZotPrime 内网部署指南

## 快速开始

```bash
# 1. 加载镜像
./load-images.sh

# 2. 一键部署
chmod +x bin/deploy-intranet.sh
./bin/deploy-intranet.sh
```

## 详细步骤

### 第一步：加载镜像

```bash
./load-images.sh
```

将所有 Docker 镜像导入本地仓库，约需 1-3 分钟。

### 第二步：运行部署

```bash
chmod +x bin/deploy-intranet.sh
./bin/deploy-intranet.sh
```

部署脚本会自动：
1. 检查 Docker 环境
2. 配置 Elasticsearch 内核参数
3. 生成随机密钥
4. 启动全部服务
5. 执行健康检查

### 第三步：保存凭据

部署完成后屏幕上会显示所有服务的登录凭据，请务必备份。

## 访问地址

| 服务 | 地址 |
|------|------|
| Zotero API | `http://<服务器IP>:8080/` |
| Admin 面板 | `http://<服务器IP>:8082/login` |
| Portal 门户 | `http://<服务器IP>:3045/` |
| PHPMyAdmin | `http://<服务器IP>:8083/` |
| MinIO 管理 | `http://<服务器IP>:9001/` |

## 常见问题

**Q: 导入镜像时报错？**
A: 确保 Docker 已安装并运行：`docker --version`

**Q: Elasticsearch 启动失败？**
A: 执行 `sudo sysctl -w vm.max_map_count=262144`

**Q: 端口被占用？**
A: 修改 `docker-compose.yml` 中对应服务的 `ports` 映射

## 完整文档

更多信息请参考 `docs/intranet-deployment.md`
DEPLOY_EOF

# 6. 打包压缩
log_step "6/6 创建压缩包..."

cd "$BUILD_DIR"
tar czf "${PACKAGE_NAME}.tar.gz" "$PACKAGE_NAME/"

package_size=$(du -sh "${PACKAGE_NAME}.tar.gz" | awk '{print $1}')

# 清理临时目录
rm -rf "$PACKAGE_DIR"

echo ""
echo "=========================================="
echo "  打包完成！"
echo "=========================================="
echo ""
echo "  部署包: build/${PACKAGE_NAME}.tar.gz"
echo "  文件大小: ${package_size}"
echo ""
echo "  传输到内网服务器后执行:"
echo "    tar xzf ${PACKAGE_NAME}.tar.gz"
echo "    cd ${PACKAGE_NAME}"
echo "    ./load-images.sh"
echo "    ./bin/deploy-intranet.sh"
echo ""
