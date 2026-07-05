#!/bin/bash
# ZotPrime 客户端 HTTP 文件服务器
# 在内网服务器上运行:bin/serve-clients.sh
# 起一个 nginx serve intranet-package/clients/ 在 :8000
#
# 用法:
#   ./bin/serve-clients.sh                    # 默认 :8000,serve intranet-package/clients/
#   PORT=9000 ./bin/serve-clients.sh          # 自定义端口
#   DOC_ROOT=/path ./bin/serve-clients.sh     # 自定义文档根
#   ./bin/serve-clients.sh --stop             # 停止运行中的服务器

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PORT="${PORT:-8000}"
DOC_ROOT="${DOC_ROOT:-${PROJECT_DIR}/intranet-package/clients}"
CONTAINER_NAME="zotprime-client-www"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# === 停止模式 ===
if [ "${1:-}" = "--stop" ]; then
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker rm -f "${CONTAINER_NAME}" >/dev/null
        log_info "已停止 ${CONTAINER_NAME}"
    else
        log_warn "${CONTAINER_NAME} 未运行"
    fi
    exit 0
fi

# === 启动模式 ===

# 前置检查
log_step "1/4 检查文档根目录..."
if [ ! -d "$DOC_ROOT" ]; then
    log_error "文档根目录不存在: $DOC_ROOT"
    log_error "请先运行: ./bin/package-for-intranet.sh 生成客户端"
    exit 1
fi
log_info "文档根: $DOC_ROOT"
ls "$DOC_ROOT" | sed 's/^/  /'

# 检查端口占用
log_step "2/4 检查端口 ${PORT}..."
if ss -ltn 2>/dev/null | grep -q ":${PORT} "; then
    log_error "端口 ${PORT} 已被占用"
    log_info "使用其他端口: PORT=9000 $0"
    exit 2
fi

# 检测本机 IP
detect_server_ip() {
    if command -v ip &>/dev/null; then
        ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1
    elif command -v hostname &>/dev/null; then
        hostname -I 2>/dev/null | awk '{print $1}'
    else
        echo "127.0.0.1"
    fi
}
SERVER_IP="${SERVER_IP:-$(detect_server_ip)}"

# 停止已存在的容器(幂等)
log_step "3/4 启动 nginx 容器..."
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_warn "发现已存在的 ${CONTAINER_NAME},先移除"
    docker rm -f "${CONTAINER_NAME}" >/dev/null
fi

docker run -d \
    --name "${CONTAINER_NAME}" \
    --restart unless-stopped \
    -p "${PORT}:80" \
    -v "${DOC_ROOT}:/usr/share/nginx/html:ro" \
    nginx:alpine >/dev/null

# 健康检查
log_step "4/4 健康检查..."
sleep 2
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_error "容器启动失败,日志:"
    docker logs "${CONTAINER_NAME}" 2>&1 | tail -10
    exit 3
fi

if curl -fs --connect-timeout 3 "http://localhost:${PORT}/" >/dev/null; then
    log_info "✓ HTTP 200 OK"
else
    log_warn "容器启动但 HTTP 探测失败"
fi

echo ""
echo "=========================================="
echo "  ✅ 客户端 HTTP 文件服务器已启动"
echo "=========================================="
echo ""
echo "  访问地址:"
echo "    http://${SERVER_IP}:${PORT}/"
echo ""
echo "  各客户端下载:"
echo "    Win10+ (8.0.1):   http://${SERVER_IP}:${PORT}/win10plus/"
echo "    Win7  (5.0.96.3): http://${SERVER_IP}:${PORT}/win7/"
echo ""
echo "  停止服务: $0 --stop"
echo "  查看日志: docker logs ${CONTAINER_NAME}"
echo ""