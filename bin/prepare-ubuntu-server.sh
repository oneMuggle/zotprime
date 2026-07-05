#!/bin/bash
# ZotPrime Ubuntu 22.04 服务器环境准备脚本
# 幂等: 多次运行结果一致,可重复执行不破坏环境
#
# 用法:
#   ./bin/prepare-ubuntu-server.sh                    # 默认 (Asia/Shanghai)
#   ./bin/prepare-ubuntu-server.sh --tz Asia/Tokyo    # 自定义时区
#   ./bin/prepare-ubuntu-server.sh --upgrade          # 同时升级系统包
#   ./bin/prepare-ubuntu-server.sh --skip-firewall    # 跳过 UFW 配置
#   ./bin/prepare-ubuntu-server.sh --check-php85      # dry-run: 检查 PHP 8.5 构建前置
#
# 验证标准:
#   - docker --version ≥ 20.10
#   - docker compose version ≥ 2.20
#   - docker run hello-world 成功
#   - sysctl vm.max_map_count == 262144
#   - ufw status 显示 8 个端口已 allow (除非 --skip-firewall)
#   - timedatectl status 显示 NTP synchronized: yes

set -e

# === 参数解析 ===
TZ="${TZ:-Asia/Shanghai}"
DO_UPGRADE=false
SKIP_FIREWALL=false
CHECK_PHP85=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tz) TZ="$2"; shift 2 ;;
        --upgrade) DO_UPGRADE=true; shift ;;
        --skip-firewall) SKIP_FIREWALL=true; shift ;;
        --check-php85) CHECK_PHP85=true; shift ;;
        -h|--help)
            sed -n '2,18p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "未知参数: $1 (用 --help 查看用法)"; exit 64 ;;
    esac
done

# === 颜色输出 ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# === 前置检查 ===
if [ "$EUID" -eq 0 ]; then
    log_error "请不要使用 root 用户运行此脚本 (避免误操作)"
    exit 1
fi

if ! command -v apt &> /dev/null; then
    log_error "此脚本仅支持 Debian/Ubuntu 系列 (需 apt)"
    exit 2
fi

# 检测 Ubuntu 版本 (warning only,不强制)
if ! grep -qE 'Ubuntu (22\.04|24\.04)' /etc/os-release 2>/dev/null; then
    log_warn "未检测到 Ubuntu 22.04/24.04,继续尝试 (其他版本可能不兼容)"
fi

echo ""
echo "=========================================="
echo "  ZotPrime Ubuntu 22.04 环境准备"
echo "  时区: $TZ"
echo "  系统升级: $DO_UPGRADE"
echo "  防火墙: $([ "$SKIP_FIREWALL" = true ] && echo "跳过" || echo "配置")"
echo "=========================================="
echo ""

# === Step 1: 系统包更新 ===
if [ "$DO_UPGRADE" = true ]; then
    log_step "1/7 升级系统包..."
    sudo apt update
    sudo apt upgrade -y
else
    log_step "1/7 同步包索引 (跳过升级,用 --upgrade 开启)..."
    sudo apt update
fi

# === Step 2: 基础工具 ===
log_step "2/7 安装基础工具..."
BASE_PACKAGES=(curl wget git openssl ca-certificates jq gnupg lsb-release)
MISSING=()
for pkg in "${BASE_PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        MISSING+=("$pkg")
    fi
done
if [ ${#MISSING[@]} -gt 0 ]; then
    log_info "安装缺失包: ${MISSING[*]}"
    sudo apt install -y "${MISSING[@]}"
else
    log_info "所有基础工具已安装"
fi

# === Step 3: Docker Engine ===
log_step "3/7 安装 Docker Engine..."
if ! command -v docker &> /dev/null; then
    log_info "下载并执行 get.docker.com..."
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sudo sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh
    log_info "Docker 安装完成"
else
    log_info "Docker 已安装: $(docker --version)"
fi

# Docker 版本检查 (≥ 20.10)
DOCKER_VER=$(docker --version | awk '{print $3}' | sed 's/,//')
DOCKER_MAJOR=$(echo "$DOCKER_VER" | cut -d. -f1)
DOCKER_MINOR=$(echo "$DOCKER_VER" | cut -d. -f2)
if [ "$DOCKER_MAJOR" -lt 20 ] || { [ "$DOCKER_MAJOR" -eq 20 ] && [ "$DOCKER_MINOR" -lt 10 ]; }; then
    log_error "Docker 版本 $DOCKER_VER 过低,需要 ≥ 20.10"
    exit 3
fi

# Docker Compose 检查 (≥ 2.20)
if ! docker compose version &>/dev/null; then
    log_warn "Docker Compose 插件缺失,尝试安装..."
    sudo apt install -y docker-compose-plugin
fi
COMPOSE_VER=$(docker compose version --short 2>/dev/null | sed 's/v//')
COMPOSE_MAJOR=$(echo "$COMPOSE_VER" | cut -d. -f1)
COMPOSE_MINOR=$(echo "$COMPOSE_VER" | cut -d. -f2)
if [ "$COMPOSE_MAJOR" -lt 2 ] || { [ "$COMPOSE_MAJOR" -eq 2 ] && [ "$COMPOSE_MINOR" -lt 20 ]; }; then
    log_warn "Docker Compose $COMPOSE_VER 偏低 (推荐 ≥ 2.20),不影响但请考虑升级"
fi

# 启用并启动 Docker 服务
sudo systemctl enable --now docker
log_info "Docker 服务已启用"

# 当前用户加入 docker 组
if ! groups "$USER" | grep -q '\bdocker\b'; then
    sudo usermod -aG docker "$USER"
    log_info "已将 $USER 加入 docker 组 (新会话生效,或运行: newgrp docker)"
else
    log_info "$USER 已在 docker 组中"
fi

# === Step 4: 内核参数 (Elasticsearch 推荐) ===
log_step "4/7 配置内核参数..."
SYSCTL_FILE="/etc/sysctl.d/99-zotprime.conf"
if [ ! -f "$SYSCTL_FILE" ] || ! grep -q "vm.max_map_count=262144" "$SYSCTL_FILE"; then
    sudo tee "$SYSCTL_FILE" >/dev/null <<'EOF'
# ZotPrime: Elasticsearch 推荐的内存映射数
vm.max_map_count=262144
# ZotPrime: 提高文件句柄上限 (MinIO/ES 需要)
fs.file-max=2097152
EOF
    sudo sysctl -p "$SYSCTL_FILE"
    log_info "已设置并持久化 vm.max_map_count=262144"
else
    log_info "vm.max_map_count=262144 已配置"
fi

# 文件句柄 ulimit
LIMITS_FILE="/etc/security/limits.d/99-zotprime.conf"
if [ ! -f "$LIMITS_FILE" ]; then
    sudo tee "$LIMITS_FILE" >/dev/null <<'EOF'
# ZotPrime: MinIO/ES 推荐文件句柄
* soft nofile 65536
* hard nofile 65536
EOF
    log_info "已设置 ulimit nofile=65536"
else
    log_info "ulimit nofile 已配置"
fi

# === Step 5: 关闭 swap (Elasticsearch 推荐) ===
log_step "5/7 关闭 swap..."
if [ "$(swapon --show --noheadings 2>/dev/null | wc -l)" -gt 0 ]; then
    sudo swapoff -a
    # 注释 /etc/fstab 中的 swap 行 (幂等)
    if grep -qE '^\s*[^#]*\bswap\b' /etc/fstab; then
        sudo sed -i.bak '/\bswap\b/s/^/#/' /etc/fstab
        log_info "swap 已关闭 + fstab 已注释 (备份: /etc/fstab.bak)"
    else
        log_info "swap 已关闭 (fstab 中无 swap 行)"
    fi
else
    log_info "swap 已关闭"
fi

# === Step 6: 时区 + 时间同步 ===
log_step "6/7 配置时区 + 时间同步..."
if [ "$(timedatectl show -p Timezone --value 2>/dev/null)" != "$TZ" ]; then
    sudo timedatectl set-timezone "$TZ"
    log_info "时区已设为 $TZ"
else
    log_info "时区已是 $TZ"
fi

# 启用 NTP
if ! timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q yes; then
    sudo timedatectl set-ntp true
    log_info "已启用 NTP 同步"
fi

# === Step 7: 防火墙 ===
if [ "$SKIP_FIREWALL" = true ]; then
    log_step "7/7 跳过防火墙配置 (--skip-firewall)"
else
    log_step "7/7 配置 UFW 防火墙..."
    if ! command -v ufw &>/dev/null; then
        log_info "安装 UFW..."
        sudo apt install -y ufw
    fi

    # 幂等: 逐条 allow,跳过已存在的规则
    declare -A UFW_RULES=(
        ["22/tcp"]="SSH"
        ["8080/tcp"]="Zotero API (dataserver)"
        ["8081/tcp"]="Stream Server (WebSocket)"
        ["8082/tcp"]="Admin Panel"
        ["3045/tcp"]="Portal"
        ["8083/tcp"]="PHPMyAdmin"
        ["9000/tcp"]="MinIO API"
        ["9001/tcp"]="MinIO Console"
    )
    for rule in "${!UFW_RULES[@]}"; do
        if ! sudo ufw status | grep -qE "^\s*${rule}\s+ALLOW"; then
            sudo ufw allow "$rule" comment "${UFW_RULES[$rule]}" >/dev/null
            log_info "  allow $rule (${UFW_RULES[$rule]})"
        fi
    done

    # 启用 UFW (幂等)
    if ! sudo ufw status | grep -q "Status: active"; then
        sudo ufw --force enable
        log_info "UFW 已启用"
    else
        log_info "UFW 已启用"
    fi

    # 安全提示
    log_warn "MinIO 9000/9001 仅限内网 IP 段访问,切勿对公网开放"
fi

# === 验证 ===
log_step "验证..."
echo ""
VERIFY_PASS=true

# Docker hello-world
if docker run --rm hello-world &>/dev/null; then
    log_info "  ✓ docker run hello-world 成功"
else
    log_error "  ✗ docker run hello-world 失败"
    VERIFY_PASS=false
fi

# vm.max_map_count
ACTUAL_MAP_COUNT=$(sysctl -n vm.max_map_count)
if [ "$ACTUAL_MAP_COUNT" -ge 262144 ]; then
    log_info "  ✓ vm.max_map_count=$ACTUAL_MAP_COUNT"
else
    log_error "  ✗ vm.max_map_count=$ACTUAL_MAP_COUNT (< 262144)"
    VERIFY_PASS=false
fi

# NTP
if timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q yes; then
    log_info "  ✓ NTP synchronized"
else
    log_warn "  ⚠ NTP 未同步 (可能需等待几秒)"
fi

# UFW
if [ "$SKIP_FIREWALL" = false ]; then
    if sudo ufw status | grep -q "Status: active"; then
        RULE_COUNT=$(sudo ufw status | grep -cE "ALLOW.*tcp")
        log_info "  ✓ UFW active with $RULE_COUNT rules"
    else
        log_error "  ✗ UFW 未启用"
        VERIFY_PASS=false
    fi
fi

# === PHP 8.5 dry-run 检查 (可选) ===
if [ "$CHECK_PHP85" = true ]; then
    log_step "PHP 8.5 dry-run 检查..."
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    if [ -f "$PROJECT_DIR/stack/dataserver/ds.Dockerfile" ]; then
        cd "$PROJECT_DIR/stack"
        if DOCKER_BUILDKIT=1 docker build -f dataserver/ds.Dockerfile -t uniuu/zotprime-dataserver:check-pr0 dataserver/ &>/dev/null 2>&1; then
            log_info "  ✓ dataserver 镜像构建成功"
            docker run --rm --entrypoint="" uniuu/zotprime-dataserver:check-pr0 php -v 2>/dev/null | head -1
            docker rmi uniuu/zotprime-dataserver:check-pr0 &>/dev/null || true
        else
            log_error "  ✗ dataserver 构建失败 - 见 docs/technical/php85-verification-report.md"
            VERIFY_PASS=false
        fi
    else
        log_warn "  ⚠ 未找到 ds.Dockerfile,跳过"
    fi
fi

echo ""
echo "=========================================="
if [ "$VERIFY_PASS" = true ]; then
    echo "  ✅ 环境准备完成！"
else
    echo "  ⚠️  环境准备完成但有警告,请检查上方输出"
fi
echo "=========================================="
echo ""
echo "  下一步:"
echo "    1. 如果当前会话未识别 docker 组权限,运行: newgrp docker"
echo "    2. 部署 ZotPrime:"
SCRIPT_DIR_END="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR_END="$(cd "$SCRIPT_DIR_END/.." && pwd)"
echo "       cd $PROJECT_DIR_END"
echo "       ./bin/deploy-intranet.sh"
echo ""
if [ "$VERIFY_PASS" = false ]; then
    exit 1
fi