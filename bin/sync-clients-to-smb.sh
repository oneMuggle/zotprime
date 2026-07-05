#!/bin/bash
# ZotPrime 客户端 SMB 共享同步脚本
# 把 intranet-package/clients/ 同步到 SMB 共享目录 (samba mount)
#
# 用法:
#   ./bin/sync-clients-to-smb.sh /mnt/smb-share/zotprime/clients
#   SMB_TARGET=//fileserver/zotprime/clients ./bin/sync-clients-to-smb.sh
#
# 前置:目标 SMB 共享已挂载到本地路径,或使用 cifs-utils 的 mount 命令

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 参数解析
SMB_TARGET="${1:-${SMB_TARGET:-/mnt/zotprime-clients}}"
SRC_DIR="${SRC_DIR:-${PROJECT_DIR}/intranet-package/clients}"

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
echo "  ZotPrime 客户端 SMB 同步"
echo "=========================================="
echo ""

# 前置检查
log_step "1/4 检查源目录..."
if [ ! -d "$SRC_DIR" ]; then
    log_error "源目录不存在: $SRC_DIR"
    log_error "请先运行: ./bin/package-for-intranet.sh"
    exit 1
fi
log_info "源: $SRC_DIR"
ls "$SRC_DIR" | sed 's/^/  /'

# 检查 rsync
if ! command -v rsync &>/dev/null; then
    log_error "rsync 未安装"
    log_info "安装: sudo apt install -y rsync"
    exit 2
fi

# 创建目标目录
log_step "2/4 创建目标目录..."
mkdir -p "$SMB_TARGET"
log_info "目标: $SMB_TARGET"

# 同步
log_step "3/4 同步 (rsync)..."
rsync -av --delete \
    --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r \
    "$SRC_DIR/" "$SMB_TARGET/"

# 验证
log_step "4/4 验证同步结果..."
SYNCED_FILES=$(find "$SMB_TARGET" -type f | wc -l)
SRC_FILES=$(find "$SRC_DIR" -type f | wc -l)
log_info "源文件: $SRC_FILES, 同步后文件: $SYNCED_FILES"

if [ "$SYNCED_FILES" -ne "$SRC_FILES" ]; then
    log_warn "文件数不匹配,请检查"
fi

echo ""
echo "=========================================="
echo "  ✅ 同步完成"
echo "=========================================="
echo ""
echo "  用户访问路径 (Windows 资源管理器):"
SMB_UNC_PATH=$(echo "$SMB_TARGET" | sed 's|^/mnt/|\\\\|; s|^/|\\\\|; s|/|\\|g')
echo "    \\\\${SMB_UNC_PATH}\\"
echo ""
echo "  或 SMB URL:"
echo "    smb://${SMB_TARGET}"
echo ""
echo "  各子目录:"
echo "    \\\\${SMB_UNC_PATH}\\win10plus\\"
echo "    \\\\${SMB_UNC_PATH}\\win7\\"
echo ""