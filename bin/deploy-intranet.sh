#!/bin/bash
# ZotPrime 内网一键部署脚本
# 支持两种模式：本地构建（完全离线）和 Docker Hub 拉取（需联网）
#
# Usage:
#   ./bin/deploy-intranet.sh              # 交互式部署
#   MODE=build ./bin/deploy-intranet.sh   # 强制本地构建模式
#   MODE=pull ./bin/deploy-intranet.sh    # 强制 Docker Hub 拉取模式

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

VER="${IMAGE_TAG:-v3.2.0}"
MODE="${MODE:-auto}"
ENABLE_ADMIN="${ENABLE_ADMIN:-true}"
ENABLE_PORTAL="${ENABLE_PORTAL:-true}"
SERVER_IP=""

check_docker() {
    command -v docker &> /dev/null && docker compose version &> /dev/null
}

check_internet() {
    curl -s --connect-timeout 3 https://hub.docker.com &> /dev/null || \
    ping -c1 -W2 registry-1.docker.io &> /dev/null
}

install_docker() {
    log_step "安装 Docker..."
    if command -v apt &> /dev/null; then
        sudo apt update
        sudo apt install -y docker.io docker-compose-plugin || curl -fsSL https://get.docker.com | sudo sh
        sudo systemctl enable --now docker
    elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
        curl -fsSL https://get.docker.com | sudo sh
        sudo systemctl enable --now docker
    fi
    sudo usermod -aG docker "$USER"
    log_info "Docker 安装完成，请重新登录或运行: newgrp docker"
}

install_dependencies() {
    log_step "安装依赖..."
    local missing=()
    command -v openssl &> /dev/null || missing+=("openssl")
    command -v php &> /dev/null || missing+=("php-cli")
    command -v git &> /dev/null || missing+=("git")

    if [ ${#missing[@]} -eq 0 ]; then
        log_info "所有依赖已安装"
        return
    fi

    if command -v apt &> /dev/null; then
        sudo apt install -y "${missing[@]}"
    elif command -v yum &> /dev/null; then
        sudo yum install -y "${missing[@]}"
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y "${missing[@]}"
    fi
}

fix_sysctl() {
    log_step "配置 Elasticsearch 内核参数..."
    sudo sysctl -w vm.max_map_count=262144
    echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.d/99-zotprime.conf
    log_info "已设置并持久化 vm.max_map_count=262144"
}

detect_server_ip() {
    local ip=""
    if command -v ip &> /dev/null; then
        ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
    fi
    if [ -z "$ip" ]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    echo "${ip:-127.0.0.1}"
}

build_images() {
    log_step "本地构建 Docker 镜像（tag: ${VER}）..."
    chmod +x bin/build-local.sh
    bin/build-local.sh
    log_info "所有镜像构建完成"
}

pull_images() {
    log_step "从 Docker Hub 拉取镜像..."
    if ! check_internet; then
        log_error "无网络连接，无法拉取镜像"
        log_info "请使用本地构建模式: MODE=build ./bin/deploy-intranet.sh"
        exit 1
    fi
    docker compose pull
    log_info "所有镜像拉取完成"
}

generate_config() {
    log_step "生成配置..."

    local default_ip=$(detect_server_ip)
    echo ""
    echo -n "请输入服务器 IP 地址 [${default_ip}]: "
    read HOST
    SERVER_IP="${HOST:-$default_ip}"
    echo "服务器 IP: $SERVER_IP"
    echo ""

    cp .env_example .env
    [ "$SERVER_IP" != "127.0.0.1" ] && sed -i "s#SERVER_IP=127.0.0.1#SERVER_IP=$SERVER_IP#g" .env

    log_info "生成随机密钥..."
    MARIADB_ROOT_PASSWORD=$(openssl rand -hex 16)
    MARIADB_USER="zotprimeprod"
    MARIADB_PASSWORD=$(openssl rand -hex 16)
    MINIOROOTUSER="zotprimeminio"
    MINIOROOTPASSWORD=$(openssl rand -hex 16)
    API_SUPER_TOKEN=$(openssl rand -hex 32)
    API_SUPER_TOKEN_HASH=$(php -r "echo password_hash('$API_SUPER_TOKEN', PASSWORD_BCRYPT);")
    AUTH_SALT=$(openssl rand -hex 16)
    ADMIN_USERNAME="admin"
    ADMIN_PASSWORD=$(openssl rand -hex 12)
    ADMIN_EMAIL="admin@example.tld"
    WEBADMIN_USERNAME="webadmin"
    WEBADMIN_PASSWORD_PLAIN=$(openssl rand -hex 12)
    WEBADMIN_PASSWORD=$(php -r "echo password_hash('$WEBADMIN_PASSWORD_PLAIN', PASSWORD_BCRYPT, ['cost' => 12]);")
    APP_KEY=$(openssl rand -hex 32)
    PORTAL_SESSION_SECRET=$(openssl rand -hex 32)

    sed -i "s#MARIADB_ROOT_PASSWORD=''#MARIADB_ROOT_PASSWORD='$MARIADB_ROOT_PASSWORD'#g" .env
    sed -i "s#MARIADB_USER=''#MARIADB_USER='$MARIADB_USER'#g" .env
    sed -i "s#MARIADB_PASSWORD=''#MARIADB_PASSWORD='$MARIADB_PASSWORD'#g" .env
    sed -i "s#MINIOROOTUSER=''#MINIOROOTUSER='$MINIOROOTUSER'#g" .env
    sed -i "s#MINIOROOTPASSWORD=''#MINIOROOTPASSWORD='$MINIOROOTPASSWORD'#g" .env
    sed -i "s#API_SUPER_TOKEN=''#API_SUPER_TOKEN='$API_SUPER_TOKEN'#g" .env
    sed -i "s#API_SUPER_TOKEN_HASH=''#API_SUPER_TOKEN_HASH='$API_SUPER_TOKEN_HASH'#g" .env
    sed -i "s#AUTH_SALT=''#AUTH_SALT='$AUTH_SALT'#g" .env
    sed -i "s#ADMIN_USERNAME=''#ADMIN_USERNAME='$ADMIN_USERNAME'#g" .env
    sed -i "s#ADMIN_PASSWORD=''#ADMIN_PASSWORD='$ADMIN_PASSWORD'#g" .env
    sed -i "s#ADMIN_EMAIL=''#ADMIN_EMAIL='$ADMIN_EMAIL'#g" .env
    sed -i "s#WEBADMIN_USERNAME=''#WEBADMIN_USERNAME='$WEBADMIN_USERNAME'#g" .env
    sed -i "s#WEBADMIN_PASSWORD=''#WEBADMIN_PASSWORD='$WEBADMIN_PASSWORD'#g" .env
    sed -i "s#APP_KEY=''#APP_KEY='$APP_KEY'#g" .env
    sed -i "s#PORTAL_SESSION_SECRET=''#PORTAL_SESSION_SECRET='$PORTAL_SESSION_SECRET'#g" .env

    chmod 600 .env
}

show_credentials() {
    echo ""
    echo "=========================================="
    echo "  重要：请保存以下登录凭据"
    echo "=========================================="
    echo ""
    echo "  Zotero 客户端:"
    echo "    用户名: $ADMIN_USERNAME"
    echo "    密码:   $ADMIN_PASSWORD"
    echo ""
    echo "  Admin 管理面板 ($SERVER_IP:8082):"
    echo "    用户名: $WEBADMIN_USERNAME"
    echo "    密码:   $WEBADMIN_PASSWORD_PLAIN"
    echo ""
    echo "  MinIO Web UI ($SERVER_IP:9001):"
    echo "    用户名: $MINIOROOTUSER"
    echo "    密码:   $MINIOROOTPASSWORD"
    echo ""
    echo "  PHPMyAdmin ($SERVER_IP:8083):"
    echo "    用户名: root"
    echo "    密码:   $MARIADB_ROOT_PASSWORD"
    echo ""
    echo "=========================================="
    echo ""
}

start_services() {
    log_step "启动服务..."
    docker compose up -d
    sleep 5

    local profiles=""
    $ENABLE_ADMIN && profiles="$profiles --profile admin"
    $ENABLE_PORTAL && profiles="$profiles --profile portal"
    [ -n "$profiles" ] && docker compose $profiles up -d

    log_info "服务启动完成"
}

health_check() {
    log_step "执行健康检查..."
    echo ""

    local passed=0 total=0

    local services=("Zotero API:http://${SERVER_IP}:8080/:200"
                    "Stream Server:http://${SERVER_IP}:8081/:200"
                    "MinIO:http://${SERVER_IP}:9000/minio/health/live:200"
                    "PHPMyAdmin:http://${SERVER_IP}:8083/:200")

    $ENABLE_ADMIN && services+=("Admin Panel:http://${SERVER_IP}:8082/login:200")
    $ENABLE_PORTAL && services+=("Portal:http://${SERVER_IP}:3045/:200")

    for entry in "${services[@]}"; do
        IFS=':' read -r name proto addr path expected <<< "$entry"
        url="${proto}//${addr}${path}"
        total=$((total + 1))
        local code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null || echo "000")
        if [ "$code" = "$expected" ]; then
            echo -e "  ${GREEN}✓${NC} $name: $code"
            passed=$((passed + 1))
        else
            echo -e "  ${RED}✗${NC} $name: $code (期望 $expected)"
        fi
    done

    echo ""
    if [ $passed -eq $total ]; then
        log_info "所有健康检查通过 ($passed/$total)"
    else
        log_warn "$passed/$total 通过，部分服务可能还在启动中"
    fi

    # 容器状态
    local running=$(docker compose ps | grep -c "running" || echo "0")
    log_info "运行中容器: $running"
}

# === Win7 兼容：按 Windows 版本分发客户端 (feature/win7-compatibility) ===
distribute_windows_client() {
    local target_user="$1"
    local manifest="intranet-package/clients-manifest.json"
    if [ ! -f "$manifest" ]; then
        log_error "manifest not found: $manifest"
        return 1
    fi

    # 探测 Windows 版本
    local win_ver
    if ! win_ver=$(bash bin/detect-win-version.sh --probe 2>/dev/null); then
        log_warn "Cannot detect Windows version, defaulting to win10plus"
        win_ver="win10plus"
    fi
    log_info "Detected Windows version: $win_ver"

    # 按版本选 manifest 字段
    local client_field
    case "$win_ver" in
        win7|win8|xp) client_field="win7" ;;
        win10|win11) client_field="win10plus" ;;
        *)
            log_warn "Unknown version '$win_ver', defaulting to win10plus"
            client_field="win10plus"
            ;;
    esac

    # 解析 manifest
    local installer
    installer=$(jq -r ".clients.$client_field.installer" "$manifest")
    if [ "$installer" = "null" ] || [ -z "$installer" ]; then
        log_error "No installer in manifest for $client_field"
        return 1
    fi

    # 分发（伪代码，按现有 deploy 实际推送方式替换）
    log_info "Distributing $installer to $target_user (OS=$win_ver)"
    # ... existing push logic ...
}

main() {
    echo ""
    echo "=========================================="
    echo "  ZotPrime 内网一键部署"
    echo "  版本: ${VER}"
    echo "=========================================="
    echo ""

    if [ "$EUID" -eq 0 ]; then
        log_error "请不要使用 root 用户运行此脚本"
        exit 1
    fi

    # 1. Docker
    log_step "1/6 检查 Docker..."
    if ! check_docker; then
        log_warn "Docker 未安装，正在安装..."
        install_docker
    else
        log_info "Docker $(docker --version) 已就绪"
    fi

    # 2. 依赖
    log_step "2/6 检查依赖..."
    install_dependencies

    # 3. 内核参数
    local map_count=$(sysctl -n vm.max_map_count 2>/dev/null || echo "65530")
    if [ "$map_count" -lt 262144 ]; then
        fix_sysctl
    else
        log_info "vm.max_map_count=$map_count (OK)"
    fi

    # 4. 镜像
    log_step "3/6 获取镜像..."
    if [ "$MODE" = "auto" ]; then
        if check_internet; then
            log_info "检测到网络，默认从 Docker Hub 拉取"
            read -p "使用 Docker Hub 拉取？(y=拉取, n=本地构建): " -n 1 -r
            echo
            [[ $REPLY =~ ^[Yy]$ ]] && MODE="pull" || MODE="build"
        else
            log_info "无网络，使用本地构建"
            MODE="build"
        fi
    fi

    [ "$MODE" = "build" ] && build_images || pull_images

    # 5. 配置
    log_step "4/6 生成配置..."
    generate_config
    show_credentials

    # 6. 启动
    log_step "5/6 启动服务..."
    start_services

    # 7. 健康检查
    log_step "6/6 服务健康检查..."
    log_info "等待服务启动（30秒）..."
    sleep 30
    health_check

    # 完成
    echo ""
    echo "=========================================="
    echo "  部署完成！"
    echo "=========================================="
    echo ""
    echo "  访问地址:"
    echo "    Zotero API:     http://${SERVER_IP}:8080/"
    echo "    Stream Server:  http://${SERVER_IP}:8081/"
    $ENABLE_ADMIN && echo "    Admin 面板:     http://${SERVER_IP}:8082/login"
    $ENABLE_PORTAL && echo "    Portal 门户:    http://${SERVER_IP}:3045/"
    echo "    PHPMyAdmin:     http://${SERVER_IP}:8083/"
    echo "    MinIO Web UI:   http://${SERVER_IP}:9001/"
    echo ""

    # 7. 客户端分发指引（feature/intranet-win7-integration）
    #    main() 在 server 上跑, 无法直接探测 Win 客户端机器的 OS,
    #    所以输出指引让运维人员按目标机器 OS 选客户端包分发.
    if [ -d "intranet-package/clients/win10plus" ] || [ -d "intranet-package/clients/win7" ]; then
        echo "  客户端安装包 (按目标机器 OS 选):"
        if [ -d "intranet-package/clients/win10plus" ]; then
            echo "    Win10 / Win11 → intranet-package/clients/win10plus/Zotero-8.0.1_win-x86_64-setup.exe"
        fi
        if [ -d "intranet-package/clients/win7" ]; then
            echo "    Win7 / Win8.1  → intranet-package/clients/win7/Zotero-5.0.96.3_win-x86_64-setup.exe"
        fi
        echo "    (Win7 客户端需先装 VC++ 2013 Redist, 详见 docs/user-manual/10-win7-installation.md)"
        echo "    客户端连 dataserver 时, dataserver URL 改成本机:  http://${SERVER_IP}:8080/"
        echo ""
    fi

    # 8. PR#4 客户端分发: 自动启动 HTTP 文件服务器
    if [ -d "intranet-package/clients" ]; then
        echo "  客户端 HTTP 文件服务器 (PR#4):"
        if [ -x "bin/serve-clients.sh" ]; then
            if PORT="${CLIENT_HTTP_PORT:-8000}" bin/serve-clients.sh > /tmp/serve-clients.log 2>&1; then
                echo "    ✅ HTTP 服务器: http://${SERVER_IP}:${CLIENT_HTTP_PORT:-8000}/"
                echo "       Win10+: http://${SERVER_IP}:${CLIENT_HTTP_PORT:-8000}/win10plus/"
                echo "       Win7:   http://${SERVER_IP}:${CLIENT_HTTP_PORT:-8000}/win7/"
                echo "       (停止: bin/serve-clients.sh --stop)"
            else
                echo "    ⚠ HTTP 服务器启动失败 (端口 ${CLIENT_HTTP_PORT:-8000} 可能被占用)"
                echo "      手动启动: PORT=9000 bin/serve-clients.sh"
            fi
        else
            echo "    bin/serve-clients.sh 不可执行,跳过"
        fi
        echo ""
    fi

    echo "  常用命令:"
    echo "    查看状态:  docker compose ps"
    echo "    查看日志:  docker compose logs -f"
    echo "    停止服务:  docker compose down"
    echo "    用户管理:  ./bin/admin.sh docker user list"
    echo ""
    echo "  请务必备份 .env 文件: cp .env .env.backup"
    echo ""
}

main "$@"
