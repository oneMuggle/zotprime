# ZotPrime 内网部署指南

**版本:** v3.2.0  
**最后更新:** 2026-05-21  
**适用范围:** 系统管理员在内网/离线环境部署 ZotPrime

---

## 目录

1. [概述](#1-概述)
2. [环境要求](#2-环境要求)
3. [部署方式对比](#3-部署方式对比)
4. [一键部署](#4-一键部署)
5. [手动部署](#5-手动部署)
6. [服务验证](#6-服务验证)
7. [防火墙配置](#7-防火墙配置)
8. [日常运维](#8-日常运维)
9. [常见问题](#9-常见问题)

---

## 1. 概述

ZotPrime 是一个自托管的 Zotero 文献管理服务平台，包含 13 个 Docker 容器组件。本文档提供在内网（无互联网连接）环境中的完整部署方案。

### 1.1 架构概览

```
┌─────────────────────────────────────────────────────┐
│                  内网服务器                           │
│                                                     │
│  客户端/浏览器                                       │
│       │                                             │
│       ▼                                             │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │ Zotero API  │  │ Stream Server│  │ Admin 面板  │ │
│  │   :8080     │  │    :8081     │  │   :8082    │ │
│  └──────┬──────┘  └──────┬───────┘  └─────┬──────┘ │
│         │                │                 │        │
│  ┌──────▼────────────────▼─────────────────▼──────┐ │
│  │              基础服务层                          │ │
│  │  MariaDB │ Elasticsearch │ Redis │ Memcached   │ │
│  │  MinIO   │ LocalStack    │ ...                 │ │
│  └────────────────────────────────────────────────┘ │
│                                                     │
│  数据卷持久化: dbdata, miniodata, admin-data 等      │
└─────────────────────────────────────────────────────┘
```

### 1.2 组件清单

| 组件 | 端口 | 说明 |
|------|------|------|
| Zotero API (dataserver) | 8080 | 客户端连接端点 |
| Stream Server | 8081 | WebSocket 实时同步 |
| Admin 管理面板 | 8082 | Web 管理界面（可选） |
| Portal 用户门户 | 3045 | 用户注册门户（可选） |
| PHPMyAdmin | 8083 | 数据库管理 |
| MinIO S3 API | 9000 | 对象存储 |
| MinIO Web UI | 9001 | 对象存储管理界面 |
| MariaDB | (内部) | 关系数据库 |
| Elasticsearch | (内部) | 全文搜索 |
| Redis | (内部) | 缓存 |
| Memcached | (内部) | 会话缓存 |

---

## 2. 环境要求

### 2.1 硬件要求

| 规模 | CPU | 内存 | 存储 |
|------|-----|------|------|
| 10 人以下 | 4 核 | 8 GB | 50 GB SSD |
| 50 人以下 | 4 核 | 8 GB | 200 GB SSD |
| 100 人以上 | 8 核+ | 16 GB+ | 500 GB+ SSD |

> **注意：** Elasticsearch 默认分配 1GB JVM 堆内存，MariaDB 约 512MB，整体基础内存占用约 3-4GB。

### 2.2 操作系统

- Ubuntu 20.04+ / 22.04+ / 24.04+（推荐）
- Debian 11+
- CentOS 8+ / RHEL 8+
- 其他支持 Docker 的 Linux 发行版

### 2.3 软件要求

| 软件 | 最低版本 | 说明 |
|------|----------|------|
| Docker Engine | 20.10+ | 容器运行时 |
| Docker Compose | 2.20+ | 容器编排 |
| OpenSSL | 任意版本 | 密钥生成 |
| PHP CLI | 8.0+ | 密码哈希 |
| Git | 2.0+ | 代码管理 |

### 2.4 关键内核参数

Elasticsearch 要求 `vm.max_map_count >= 262144`：

```bash
# 检查当前值
sysctl vm.max_map_count

# 临时设置（重启后失效）
sudo sysctl -w vm.max_map_count=262144

# 永久设置
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.d/99-zotprime.conf
```

### 2.5 端口要求

确保以下端口未被占用：

| 端口 | 用途 | 是否可修改 |
|------|------|------------|
| 8080 | Zotero API | 是，修改 docker-compose.yml |
| 8081 | Stream Server | 是 |
| 8082 | Admin 面板 | 是 |
| 8083 | PHPMyAdmin | 是 |
| 9000 | MinIO API | 是 |
| 9001 | MinIO Web | 是 |
| 3045 | Portal | 是 |

---

## 3. 部署方式对比

| 特性 | 一键脚本 | 手动部署 |
|------|----------|----------|
| 复杂度 | 低，一条命令 | 中，需要逐步操作 |
| 耗时 | 5-60 分钟（取决于模式） | 10-70 分钟 |
| 适用场景 | 快速部署 | 需要精细控制 |
| 子模块处理 | 自动 | 手动 |
| 健康检查 | 自动 | 手动验证 |

### 3.1 镜像获取方式

| 方式 | 网络要求 | 耗时 | 适用场景 |
|------|----------|------|----------|
| Docker Hub 拉取 | 需要互联网 | 5-10 分钟 | 服务器可上网 |
| 本地构建 | 完全离线 | 30-60 分钟 | 内网/无网络环境 |

---

## 4. 一键部署

### 4.1 准备工作

确保服务器满足 [环境要求](#2-环境要求)，然后下载部署脚本和项目代码。

**有网络的服务器：**

```bash
# 克隆项目（含子模块）
git clone --recursive https://github.com/uniuuu/zotprime.git
cd zotprime
```

**无网络的内网服务器：**

```bash
# 1. 在能上网的机器上打包项目
git clone --recursive https://github.com/uniuuu/zotprime.git
tar czf zotprime.tar.gz zotprime/

# 2. 通过 U 盘/内网文件共享将 zotprime.tar.gz 传到内网服务器

# 3. 在内网服务器上解压
mkdir -p /opt/zotprime
tar xzf zotprime.tar.gz -C /opt/zotprime --strip-components=1
cd /opt/zotprime
```

### 4.2 运行部署脚本

```bash
chmod +x bin/deploy-intranet.sh
./bin/deploy-intranet.sh
```

脚本会自动：

1. 检查并安装 Docker（如未安装）
2. 安装 OpenSSL、PHP-CLI 等依赖
3. 配置 Elasticsearch 内核参数
4. 检测网络环境，选择镜像获取方式
5. 生成随机密钥和配置文件
6. 启动所有服务
7. 执行健康检查

**交互式选择模式：**

脚本检测到网络时会询问镜像获取方式：

```
检测到网络，默认从 Docker Hub 拉取
使用 Docker Hub 拉取？(y=拉取, n=本地构建):
```

**非交互式部署（适合自动化）：**

```bash
# 强制本地构建（完全离线）
MODE=build ./bin/deploy-intranet.sh

# 强制 Docker Hub 拉取
MODE=pull ./bin/deploy-intranet.sh

# 指定镜像版本
IMAGE_TAG=v3.2.0 ./bin/deploy-intranet.sh
```

### 4.3 保存凭据

脚本执行过程中会显示所有服务的登录凭据，**请务必备份**：

```
==========================================
  重要：请保存以下登录凭据
==========================================

  Zotero 客户端:
    用户名: admin
    密码:   <随机生成的密码>

  Admin 管理面板 (192.168.1.100:8082):
    用户名: webadmin
    密码:   <随机生成的密码>

  ...
==========================================
```

所有凭据也保存在 `.env` 文件中：

```bash
# 备份配置文件（包含所有密钥）
cp .env .env.backup_$(date +%Y%m%d)
```

---

## 5. 手动部署

如果需要更精细的控制，请按以下步骤操作。

### 5.1 安装 Docker

**Ubuntu/Debian：**

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-plugin openssl php-cli git
sudo systemctl enable --now docker

# 将当前用户加入 docker 组（避免每次 sudo）
sudo usermod -aG docker $USER
newgrp docker
```

**CentOS/RHEL：**

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
```

### 5.2 配置内核参数

```bash
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.d/99-zotprime.conf
```

### 5.3 获取项目代码

```bash
# 有网络
git clone --recursive https://github.com/uniuuu/zotprime.git
cd zotprime

# 无网络：通过 U 盘传输已打包的项目文件（含子模块）
tar xzf zotprime.tar.gz
cd zotprime
```

### 5.4 获取镜像

#### 方式 A：本地构建（完全离线）

```bash
chmod +x bin/build-local.sh
./bin/build-local.sh

# 验证镜像
docker images | grep zotprime
```

输出示例：

```
uniuu/zotprime-dataserver    v3.2.0    ...    2 hours ago
uniuu/zotprime-db            v3.2.0    ...    2 hours ago
uniuu/zotprime-admin         v3.2.0    ...    2 hours ago
...（共 13 个镜像）
```

#### 方式 B：Docker Hub 拉取（需联网）

```bash
# 登录避免匿名拉取限流
docker login

# 拉取所有镜像
docker compose pull
```

### 5.5 生成配置

```bash
# 1. 复制环境变量模板
cp .env_example .env

# 2. 设置服务器 IP
# 获取服务器内网 IP
ip addr show | grep 'inet ' | grep -v 127.0.0.1
# 假设输出为 192.168.1.100
sed -i 's#SERVER_IP=127.0.0.1#SERVER_IP=192.168.1.100#g' .env

# 3. 生成随机密钥
# 方法一：使用安装脚本
./bin/install.sh

# 方法二：手动生成并填入
# 生成各密钥并替换 .env 中对应变量
MARIADB_ROOT_PASSWORD=$(openssl rand -hex 16)
ADMIN_PASSWORD=$(openssl rand -hex 12)
# ... 参考 .env_example 中的变量名逐一生成
```

### 5.6 启动服务

```bash
# 基础服务
docker compose up -d

# 包含 Admin 面板和 Portal 门户
docker compose --profile admin --profile portal up -d

# 查看启动日志
docker compose logs -f --tail=20
```

---

## 6. 服务验证

### 6.1 检查容器状态

```bash
docker compose ps
```

预期输出（部分）：

```
NAME                        STATUS          PORTS
zotprime-db                 Up (healthy)    3306/tcp
zotprime-dataserver         Up (healthy)    8080/tcp
zotprime-elasticsearch      Up              9200/tcp, 9300/tcp
zotprime-redis              Up              6379/tcp
zotprime-minio              Up              9000/tcp, 9001/tcp
...
```

### 6.2 HTTP 健康检查

```bash
SERVER_IP="192.168.1.100"  # 替换为实际 IP

# Zotero API - 应返回 200
curl -s -o /dev/null -w "%{http_code}\n" http://$SERVER_IP:8080/

# Stream Server - 应返回 200
curl -s -o /dev/null -w "%{http_code}\n" http://$SERVER_IP:8081/

# Admin Panel - 应返回 200
curl -s -o /dev/null -w "%{http_code}\n" http://$SERVER_IP:8082/login

# Portal - 应返回 200
curl -s -o /dev/null -w "%{http_code}\n" http://$SERVER_IP:3045/

# MinIO - 应返回 200
curl -s -o /dev/null -w "%{http_code}\n" http://$SERVER_IP:9000/minio/health/live

# PHPMyAdmin - 应返回 200
curl -s -o /dev/null -w "%{http_code}\n" http://$SERVER_IP:8083/
```

### 6.3 组件级检查

```bash
# Elasticsearch 集群状态
docker compose exec zotprime-elasticsearch curl -s http://localhost:9200/_cluster/health | grep status
# 预期: "status":"green" 或 "status":"yellow"

# Redis 响应
docker compose exec zotprime-redis redis-cli ping
# 预期: PONG

# MariaDB 连接
docker compose exec zotprime-db mysql -u root -p"$MARIADB_ROOT_PASSWORD" -e "SELECT 1;"
# 预期: 返回 1

# MinIO 存储桶
docker compose exec minio mc alias set myminio http://localhost:9000 zotprimeminio <密码>
docker compose exec minio mc ls myminio
```

### 6.4 客户端连接测试

#### 6.4.1 获取客户端安装包

部署包 `intranet-package/clients/` 目录已包含按目标机器 OS 分类的 Zotero 桌面客户端安装包：

| 目录 | 适用系统 | Zotero 版本 | 文件 |
|------|----------|-------------|------|
| `clients/win10plus/` | Windows 10 / Windows 11 | 8.0.1 | `Zotero-8.0.1_win-x86_64-setup.exe` |
| `clients/win7/` | Windows 7 SP1 / Windows 8.1 | 5.0.96.3 | `Zotero-5.0.96.3_win-x86_64-setup.exe` |
| `clients/clients-manifest.json` | 客户端清单（含 sha256 + min_os 字段） | - | - |

**获取方式**（任选其一）：

- **U 盘/文件共享**：将 `intranet-package/clients/` 拷贝到 U 盘或内网 SMB/NFS 共享
- **内网 HTTP 服务**：在内网服务器临时启动 `python3 -m http.server -d intranet-package/clients 8088`，客户端浏览器访问 `http://<SERVER_IP>:8088/`
- **邮件/IM 附件**：直接发送 .exe（注意内网病毒扫描）

**按目标机器 OS 选包**（如果不确定）：

在 Win 客户端机器上运行 `bin/detect-win-version.sh --probe`（从部署包复制过来），输出 `win7`/`win10`/`win11` 等。

#### 6.4.2 Win7 客户端前置依赖

Win7 / Win8.1 客户端（5.0.96.3）需要先安装 [VC++ 2013 Redist x64](https://www.microsoft.com/en-us/download/details.aspx?id=40784)。Win10+ 不需要。

#### 6.4.3 安装与配置

在目标机器上安装后：

1. 打开 Zotero → 编辑 → 首选项 → 同步
2. 设置数据同步 URL：`http://<SERVER_IP>:8080/`
3. 设置文件同步 URL：`http://<SERVER_IP>:8080/`
4. 输入用户名 `admin` 和安装时生成的密码
5. 点击测试连接，应提示连接成功

如果使用 Win7 客户端，配置已通过 PowerShell C 路径（`bin/set-zotero-dataserver.ps1`）注入，不需要手动改 URL。

---

## 7. 防火墙配置

### 7.1 UFW（Ubuntu）

```bash
# 允许内网网段访问（推荐，更安全）
LAN_SUBNET="192.168.1.0/24"  # 替换为实际网段

sudo ufw allow from $LAN_SUBNET to any port 8080 proto tcp comment "Zotero API"
sudo ufw allow from $LAN_SUBNET to any port 8081 proto tcp comment "WebSocket"
sudo ufw allow from $LAN_SUBNET to any port 8082 proto tcp comment "Admin Panel"
sudo ufw allow from $LAN_SUBNET to any port 8083 proto tcp comment "PHPMyAdmin"
sudo ufw allow from $LAN_SUBNET to any port 9000 proto tcp comment "MinIO API"
sudo ufw allow from $LAN_SUBNET to any port 9001 proto tcp comment "MinIO Web"
sudo ufw allow from $LAN_SUBNET to any port 3045 proto tcp comment "Portal"

sudo ufw enable
```

### 7.2 firewalld（CentOS/RHEL）

```bash
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" port port="8080-8083" protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" port port="9000-9001" protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" port port="3045" protocol="tcp" accept'
sudo firewall-cmd --reload
```

### 7.3 安全建议

- **PHPMyAdmin（8083）和 MinIO Web（9001）** 建议仅对管理员 IP 开放
- **不要将数据库端口暴露到外网**
- 如果内网完全可信，也可以直接开放所有端口（不推荐）

---

## 8. 日常运维

### 8.1 查看服务状态

```bash
cd /opt/zotprime  # 进入项目目录

# 查看所有容器状态
docker compose ps

# 查看资源占用
docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# 查看特定服务日志
docker compose logs -f --tail=100 dataserver
docker compose logs -f --tail=100 admin

# 搜索错误日志
docker compose logs dataserver 2>&1 | grep -i error
```

### 8.2 启停服务

```bash
# 停止所有服务（数据保留）
docker compose down

# 重启所有服务
docker compose --profile admin --profile portal restart

# 重启单个服务
docker compose restart dataserver

# 停止并删除数据卷（⚠️ 不可逆！）
docker compose --profile admin --profile portal down -v
```

### 8.3 用户管理

```bash
# 创建用户
./bin/admin.sh docker user create alice alice@example.tld password123

# 查看所有用户
./bin/admin.sh docker user list

# 查看用户存储配额
./bin/admin.sh docker user quota <用户ID>

# 设置存储配额（MB）
./bin/admin.sh docker user set-quota <用户ID> 2048

# 禁用/启用用户
./bin/admin.sh docker user disable alice
./bin/admin.sh docker user enable alice

# 创建群组
./bin/admin.sh docker group create <群主ID> "群组名称" Private
```

### 8.4 Admin 面板密码重置

```bash
# 1. 生成新的 bcrypt 密码哈希
NEW_HASH=$(php -r "echo password_hash('NewPassword123', PASSWORD_BCRYPT, ['cost' => 12]);")
echo "新密码哈希: $NEW_HASH"

# 2. 替换 .env 中的密码
sed -i "s/^WEBADMIN_PASSWORD=.*/WEBADMIN_PASSWORD='$NEW_HASH'/" .env

# 3. 重启 Admin 服务
docker compose --profile admin up -d --force-recreate admin
```

### 8.5 数据备份

#### 数据库备份

```bash
#!/bin/bash
# backup-db.sh
BACKUP_DIR="/opt/zotprime/backups/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

cd /opt/zotprime

# 加载 .env 中的变量
set -a
source .env
set +a

# 备份数据库
docker compose exec -T zotprime-db mysqldump \
  -u root -p"${MARIADB_ROOT_PASSWORD}" \
  --all-databases | gzip > "$BACKUP_DIR/database.sql.gz"

echo "数据库备份完成: $BACKUP_DIR/database.sql.gz"
```

#### 完整备份（含数据卷）

```bash
#!/bin/bash
# backup-full.sh
BACKUP_DIR="/opt/zotprime/backups/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

cd /opt/zotprime

# 备份 .env
cp .env "$BACKUP_DIR/.env"

# 备份数据库
set -a; source .env; set +a
docker compose exec -T zotprime-db mysqldump \
  -u root -p"${MARIADB_ROOT_PASSWORD}" \
  --all-databases | gzip > "$BACKUP_DIR/database.sql.gz"

# 备份 Docker 数据卷
for vol in $(docker volume ls --filter name=zotprime -q); do
  vol_name=$(echo "$vol" | sed 's/zotprime_//')
  docker run --rm \
    -v "${vol}":/data:ro \
    -v "$BACKUP_DIR":/backup \
    alpine tar czf "/backup/${vol_name}.tar.gz" -C /data .
done

echo "完整备份完成: $BACKUP_DIR"
```

#### 定时备份

```bash
# 添加 cron 任务（每天凌晨 2 点备份）
crontab -e
# 添加：0 2 * * * /opt/zotprime/bin/backup-db.sh >> /var/log/zotprime-backup.log 2>&1
```

#### 恢复备份

```bash
# 恢复数据库
cd /opt/zotprime
set -a; source .env; set +a
gunzip -c backups/20260521/database.sql.gz | \
  docker compose exec -T zotprime-db mysql -u root -p"${MARIADB_ROOT_PASSWORD}"

echo "数据库恢复完成"
```

### 8.6 更新服务

#### 方式 A：Docker Hub 更新（需联网）

```bash
cd /opt/zotprime

# 拉取最新镜像
docker compose pull

# 重新创建容器
docker compose --profile admin --profile portal up -d

# 清理旧镜像
docker image prune -f
```

#### 方式 B：本地重新构建

```bash
cd /opt/zotprime

# 更新代码（如果有新代码通过 U 盘传入）
# git pull  # 内网一般无法直接 git pull

# 重新构建镜像
./bin/build-local.sh

# 重新创建容器
docker compose --profile admin --profile portal up -d

# 清理旧镜像
docker image prune -f
```

---

## 9. 常见问题

### 9.1 部署相关

**Q: Elasticsearch 启动失败？**

A: 检查 `vm.max_map_count`：

```bash
sysctl vm.max_map_count
# 如果小于 262144，执行：
sudo sysctl -w vm.max_map_count=262144
```

**Q: 某些容器一直处于 "starting" 状态？**

A: 数据库初始化需要 1-3 分钟，属于正常现象。查看日志：

```bash
docker compose logs -f zotprime-init
docker compose logs -f zotprime-db
```

**Q: 端口被占用怎么办？**

A: 修改 `docker-compose.yml` 中对应服务的 `ports` 映射，例如将 8080 改为 8090：

```yaml
dataserver:
  ports:
    - "8090:8080"  # 宿主机 8090 -> 容器 8080
```

**Q: 忘记了 .env 中的密码？**

A: 密码仅保存在 `.env` 文件中，可查看文件内容：

```bash
grep ADMIN_PASSWORD .env
grep MARIADB_ROOT_PASSWORD .env
```

如果 `.env` 文件丢失，只能重新运行安装脚本（会生成新密钥，原有数据需要手动迁移）。

### 9.2 客户端连接

**Q: 客户端同步报 401 错误？**

A: 检查用户名和密码是否正确，密码区分大小写。确认数据同步 URL 格式为 `http://<IP>:8080/`（末尾斜杠不能省略）。

**Q: 客户端连接超时？**

A: 检查：
1. 服务器 IP 是否正确
2. 防火墙是否放行了 8080 端口
3. 服务是否正常运行：`curl http://<IP>:8080/`

**Q: Win7 / Win8.1 客户端启动时报"无法启动此应用程序，因为计算机中缺少 MSVCR120.dll"？**

A: 5.0.96.3 客户端依赖 VC++ 2013 Redist x64。在 Win7 / Win8.1 机器上先装 [vcredist_x64.exe](https://www.microsoft.com/en-us/download/details.aspx?id=40784) 再装 Zotero。

**Q: Win7 客户端装好后同步报"Cannot connect to api.zotero.org"（没连到内网 dataserver）？**

A: PowerShell C 路径（`bin/set-zotero-dataserver.ps1`）未生效。手动检查：
1. 用管理员权限打开 PowerShell 5.1+：`Get-Host | Select-Object Version`
2. 重新跑 `.\bin\set-zotero-dataserver.ps1 -DataServerUrl "http://<SERVER_IP>:8080/"`
3. 重启 Zotero 客户端

或退回到 Win10+ 客户端（如果 PC 可升级到 Win10）。

**Q: Win7 客户端与 Win10+ 客户端能否同时使用？**

A: 可以。两者同步协议向后兼容（5.0 协议在 6.0~8.0 dataserver 上未变），共享同一账号。但 5.0 不支持 PDF 内置阅读器、标签 v2、新笔记格式，**字段集** 比 8.0 少，sync 时 dataserver 收到 5.0 写的字段会忽略 8.0 新字段（不冲突）。建议同一用户尽量用同一版本。

### 9.3 运维相关

**Q: 如何查看某个用户使用了多少存储空间？**

A:

```bash
./bin/admin.sh docker user quota <用户ID>
```

**Q: 磁盘空间不足怎么办？**

A:

```bash
# 检查磁盘使用
df -h

# 清理未使用的 Docker 镜像
docker image prune -a -f

# 查看 MinIO 存储桶大小
docker compose exec minio mc du myminio
```

**Q: 服务重启后数据会丢失吗？**

A: 不会。数据存储在 Docker 数据卷中（`zotprime_dbdata`、`zotprime_miniodata` 等），容器重启不会丢失数据。只有执行 `docker compose down -v` 才会删除数据卷。

**Q: 如何迁移到另一台服务器？**

A:

```bash
# 旧服务器备份
./bin/backup-full.sh

# 将备份目录拷贝到新服务器
scp -r /opt/zotprime/backups/20260521 new-server:/opt/zotprime/backups/

# 新服务器上恢复
cd /opt/zotprime
cp backups/20260521/.env .env
chmod 600 .env

# 恢复数据库
set -a; source .env; set +a
gunzip -c backups/20260521/database.sql.gz | \
  docker compose exec -T zotprime-db mysql -u root -p"${MARIADB_ROOT_PASSWORD}"
```

---

## 附录

### A. 目录结构

```
zotprime/
├── bin/
│   ├── deploy-intranet.sh    # 一键部署脚本
│   ├── install.sh            # 基础安装脚本
│   ├── build-local.sh        # 本地镜像构建脚本
│   └── admin.sh              # 用户/组管理脚本
├── stack/                    # 各服务配置与源码
├── docker-compose.yml        # Docker Compose 配置
├── .env_example              # 环境变量模板
└── .env                      # 实际环境变量（自动生成）
```

### B. 环境变量参考

| 变量 | 说明 | 示例 |
|------|------|------|
| `SERVER_IP` | 服务器 IP | `192.168.1.100` |
| `MARIADB_ROOT_PASSWORD` | 数据库 root 密码 | 自动生成 |
| `API_SUPER_TOKEN` | 管理员 API Token | 自动生成 |
| `ADMIN_USERNAME` | 首个 Zotero 用户名 | `admin` |
| `ADMIN_PASSWORD` | 首个 Zotero 密码 | 自动生成 |
| `WEBADMIN_PASSWORD` | Admin 面板密码（bcrypt） | 自动生成 |
| `MINIOROOTPASSWORD` | MinIO root 密码 | 自动生成 |

### C. 相关文档

| 文档 | 路径 | 说明 |
|------|------|------|
| 技术手册 | `docs/technical-manual.md` | 系统架构、API 参考、运维指南 |
| 用户手册 | `docs/user-manual.md` | 功能说明、操作步骤、常见问题 |
| 差距分析 | `docs/plan/2026-05-20-zotero-gap-analysis.md` | 与官方功能对比与完善方案 |
