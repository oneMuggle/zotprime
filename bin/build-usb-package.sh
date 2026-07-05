#!/bin/bash
# ZotPrime 客户端 U 盘分发包构建脚本
# 把客户端 + README.txt + SHA256SUMS 打包到 U 盘目录结构
#
# 用法:
#   ./bin/build-usb-package.sh /media/usb/ZotPrime-Setup-USB
#   USB_TARGET=/path/to/usb ./bin/build-usb-package.sh
#
# 输出目录结构:
#   ZotPrime-Setup-USB/
#   ├── README.txt
#   ├── win10plus/
#   │   └── Zotero-8.0.1_win-x86_64-setup.exe
#   ├── win7/
#   │   ├── Zotero-5.0.96.3_win-x86_64-setup.exe
#   │   ├── VC_redist.x64.exe (需要手动下载放入)
#   │   └── set-zotero-dataserver.ps1
#   └── SHA256SUMS

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

USB_TARGET="${1:-${USB_TARGET:-${PROJECT_DIR}/ZotPrime-Setup-USB}}"
SRC_DIR="${SRC_DIR:-${PROJECT_DIR}/intranet-package/clients}"
DATASERVER_URL="${DATASERVER_URL:-http://127.0.0.1:8080/}"
STREAM_URL="${STREAM_URL:-ws://127.0.0.1:8081/}"

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
echo "  ZotPrime U 盘分发包构建"
echo "=========================================="
echo ""
echo "  目标: $USB_TARGET"
echo "  源:   $SRC_DIR"
echo ""

# 前置检查
log_step "1/5 检查源..."
if [ ! -d "$SRC_DIR/win10plus" ] || [ ! -d "$SRC_DIR/win7" ]; then
    log_error "源目录不完整 (需含 win10plus/ 和 win7/)"
    log_error "请先运行: ./bin/package-for-intranet.sh"
    exit 1
fi

# 创建目录结构
log_step "2/5 创建目录结构..."
rm -rf "$USB_TARGET"
mkdir -p "$USB_TARGET/win10plus" "$USB_TARGET/win7"
log_info "已创建: $USB_TARGET"

# 复制 Win10+ 客户端
log_step "3/5 复制 Win10+ 8.0.1 客户端..."
cp "$SRC_DIR/win10plus/"*.exe "$USB_TARGET/win10plus/"
WIN10_COUNT=$(ls "$USB_TARGET/win10plus/" | wc -l)
log_info "  win10plus/: $WIN10_COUNT 个文件"

# 复制 Win7 客户端 + PS 脚本
log_step "4/5 复制 Win7 5.0.96.3 客户端..."
cp "$SRC_DIR/win7/"*.exe "$USB_TARGET/win7/"
cp "$SCRIPT_DIR/set-zotero-dataserver.ps1" "$USB_TARGET/win7/"

# 检查 VC++ Redist 是否在 U 盘目录(可选)
VCREDIST="$USB_TARGET/win7/VC_redist.x64.exe"
if [ ! -f "$VCREDIST" ]; then
    log_warn "  ⚠ VC_redist.x64.exe 不在 U 盘 (Win7 装机必需)"
    log_warn "    请从 https://aka.ms/vs/17/release/vc_redist.x64.exe 下载后放入 $USB_TARGET/win7/"
fi

WIN7_COUNT=$(ls "$USB_TARGET/win7/" | wc -l)
log_info "  win7/: $WIN7_COUNT 个文件"

# 生成 SHA256SUMS
log_step "5/5 生成 SHA256SUMS + README.txt..."
cd "$USB_TARGET"
sha256sum win10plus/*.exe win7/*.exe > SHA256SUMS 2>/dev/null || \
    sha256sum win10plus/*.exe win7/*.exe > SHA256SUMS
log_info "  SHA256SUMS 已生成 ($(wc -l < SHA256SUMS) 条)"

# 生成 README.txt (UTF-8)
cat > "$USB_TARGET/README.txt" <<EOF
================================================================
  ZotPrime 客户端安装包 (内网分发)
================================================================

本 U 盘包含 Zotero 客户端安装包,用于连接内网 ZotPrime 服务端。

服务器地址(由 IT 填写):
  - Dataserver URL: ${DATASERVER_URL}
  - Stream URL:     ${STREAM_URL}

================================================================
  Windows 10 / 11 用户 (推荐)
================================================================

1. 插入 U 盘
2. 打开 "win10plus" 文件夹
3. 双击 "Zotero-8.0.1_win-x86_64-setup.exe"
4. 按向导安装 (可全默认)
5. 启动 Zotero
6. 验证: Preferences → Sync → 显示 "Last sync time: <当前时间>"

注意:
- 客户端已内置 dataserver URL,无需手动配置
- 首次启动可能较慢 (1-2 分钟),不要关闭

================================================================
  Windows 7 SP1 / 8.1 用户
================================================================

1. 安装前置依赖 (仅首次):
   a. 双击 "win7\\VC_redist.x64.exe" 安装 VC++ 2013 Redist
   b. 如果 PowerShell < 5.0,安装 WMF 5.1:
      https://www.microsoft.com/en-us/download/details.aspx?id=54616

2. 安装 Zotero:
   - 打开 "win7" 文件夹
   - 双击 "Zotero-5.0.96.3_win-x86_64-setup.exe"
   - 按向导安装

3. 配置 dataserver URL (安装后必须做一次):
   - 以管理员身份打开 PowerShell
   - cd 到 win7 目录
   - 运行:
       .\\set-zotero-dataserver.ps1 \\
           -DataServerUrl "${DATASERVER_URL}" \\
           -StreamServerUrl "${STREAM_URL}"

4. 启动 Zotero
5. 验证: Preferences → Sync → 显示 "Last sync time: <当前时间>"

================================================================
  验证安装 (sha256sum)
================================================================

执行以下命令验证完整性 (Linux/macOS):
  cd $(basename "$USB_TARGET")
  sha256sum -c SHA256SUMS

Windows:
  certutil -hashfile <file> SHA256

================================================================
  故障排查
================================================================

- 客户端启动后 Sync 按钮灰色 → 服务器地址不对,联系 IT
- 报 "MSVCR120.dll missing" → 装 VC++ 2013 Redist
- PowerShell 报 "version < 5.0" → 装 WMF 5.1
- 其他问题 → 联系 IT,提供本 U 盘路径与截图

EOF
log_info "  README.txt 已生成"

echo ""
echo "=========================================="
echo "  ✅ U 盘分发包构建完成"
echo "=========================================="
echo ""
echo "  目录: $USB_TARGET"
du -sh "$USB_TARGET" | sed 's/^/  大小: /'
echo ""
echo "  下一步:"
echo "    1. 把整个目录拷贝到 U 盘"
echo "    2. 如未自动包含,下载 VC_redist.x64.exe 放入 win7/ 目录:"
echo "       https://aka.ms/vs/17/release/vc_redist.x64.exe"
echo "    3. 分发给用户"
echo ""