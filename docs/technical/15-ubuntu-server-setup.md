# 15. Ubuntu 22.04 服务器环境准备

> 面向系统管理员。在全新安装的 Ubuntu 22.04 LTS 服务器上,把 ZotPrime 所需的所有系统层依赖 (Docker、内核参数、防火墙、时区、文件句柄) 一次性配置好。

---

## 15.1 适用范围

- **目标系统:** Ubuntu 22.04 LTS (Jammy),也兼容 Ubuntu 24.04 LTS
- **运行用户:** 普通用户 (脚本会调用 `sudo`,**禁止 root 直接运行**)
- **执行时机:** 在 `bin/deploy-intranet.sh` 之前

## 15.2 一键脚本

`bin/prepare-ubuntu-server.sh` 是幂等脚本,可重复执行:

```bash
cd /home/fz/project/zotprime

# 标准用法 (默认时区 Asia/Shanghai)
./bin/prepare-ubuntu-server.sh

# 同时升级系统包
./bin/prepare-ubuntu-server.sh --upgrade

# 自定义时区
./bin/prepare-ubuntu-server.sh --tz Asia/Tokyo

# 跳过防火墙 (运维已有统一防火墙策略)
./bin/prepare-ubuntu-server.sh --skip-firewall

# Dry-run PHP 8.5 构建检查 (PR#0 验证用)
./bin/prepare-ubuntu-server.sh --check-php85

# 查看完整帮助
./bin/prepare-ubuntu-server.sh --help
```

## 15.3 脚本做了什么

7 步骤,每步幂等:

| # | 步骤 | 关键产物 | 幂等机制 |
|---|------|----------|----------|
| 1 | 系统包索引同步 (`apt update`) | - | 重复执行无害 |
| 2 | 安装基础工具 | curl, wget, git, openssl, jq, ... | 检查 `dpkg -s` 跳过已装包 |
| 3 | 安装 Docker Engine + Compose Plugin | `docker` 命令,`docker compose` 子命令 | 检查 `command -v docker` 跳过 |
| 4 | 配置内核参数 | `/etc/sysctl.d/99-zotprime.conf` | 检查文件+内容,避免重复写入 |
| 5 | 关闭 swap | `/etc/fstab` 注释 swap 行 + `swapoff -a` | 检查 `swapon --show` 跳过 |
| 6 | 时区 + NTP 同步 | `timedatectl set-timezone` + `set-ntp true` | 检查当前时区,NTP 标志 |
| 7 | UFW 防火墙 | 8 个 TCP 端口 allow | 检查 `ufw status` 跳过已存在规则 |

## 15.4 防火墙端口清单

| 端口 | 服务 | 注释 |
|------|------|------|
| 22/tcp | SSH | 远程管理必需 |
| 8080/tcp | Zotero API (dataserver) | 客户端连接 |
| 8081/tcp | Stream Server (WebSocket) | 实时同步 |
| 8082/tcp | Admin Panel | 管理员 Web UI |
| 3045/tcp | Portal | 用户门户 Web UI |
| 8083/tcp | PHPMyAdmin | 数据库管理 (可选,可禁用) |
| 9000/tcp | MinIO API | 对象存储 (内网限定) |
| 9001/tcp | MinIO Console | MinIO Web UI (内网限定) |

> ⚠️ **安全提示:** 9000/9001 (MinIO) 暴露 root 凭据,**严禁对公网开放**。脚本默认开启,运维需通过防火墙 ACL 限定内网 IP 段。

## 15.5 验证标准

脚本末尾会自动验证以下项:

```text
✓ docker run hello-world 成功
✓ vm.max_map_count == 262144 (Elasticsearch 要求)
✓ NTP synchronized
✓ UFW active with 8 rules
```

任何一项失败,脚本退出码 = 1。

**手动验证:**

```bash
docker --version          # 期望 ≥ 20.10
docker compose version    # 期望 ≥ 2.20
docker run --rm hello-world
sysctl vm.max_map_count   # 期望 262144
sudo ufw status numbered  # 期望 8 个 ALLOW 规则
timedatectl status        # 期望 NTP synchronized: yes
```

## 15.6 分步手动操作 (脚本不可用时的备选)

### 15.6.1 系统包与基础工具

```bash
sudo apt update
sudo apt install -y curl wget git openssl ca-certificates jq gnupg lsb-release
```

### 15.6.2 Docker Engine

```bash
# 方法 A: get.docker.com (推荐,版本新)
curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
sudo sh /tmp/get-docker.sh
rm -f /tmp/get-docker.sh

# 方法 B: apt (版本可能偏旧)
sudo apt install -y docker.io docker-compose-plugin

sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
newgrp docker  # 或重新登录
```

### 15.6.3 内核参数

```bash
sudo tee /etc/sysctl.d/99-zotprime.conf >/dev/null <<'EOF'
vm.max_map_count=262144   # Elasticsearch 要求
fs.file-max=2097152        # MinIO/ES 推荐
EOF
sudo sysctl -p /etc/sysctl.d/99-zotprime.conf
```

### 15.6.4 文件句柄

```bash
sudo tee /etc/security/limits.d/99-zotprime.conf >/dev/null <<'EOF'
* soft nofile 65536
* hard nofile 65536
EOF
```

### 15.6.5 关闭 swap (Elasticsearch 推荐)

```bash
sudo swapoff -a
sudo sed -i.bak '/\bswap\b/s/^/#/' /etc/fstab  # 备份到 /etc/fstab.bak
```

### 15.6.6 时区 + NTP

```bash
sudo timedatectl set-timezone Asia/Shanghai
sudo timedatectl set-ntp true
```

### 15.6.7 UFW 防火墙

```bash
sudo apt install -y ufw
sudo ufw allow 22/tcp comment 'SSH'
sudo ufw allow 8080/tcp comment 'Zotero API'
sudo ufw allow 8081/tcp comment 'Stream Server'
sudo ufw allow 8082/tcp comment 'Admin Panel'
sudo ufw allow 3045/tcp comment 'Portal'
sudo ufw allow 8083/tcp comment 'PHPMyAdmin'
sudo ufw allow 9000/tcp comment 'MinIO API'
sudo ufw allow 9001/tcp comment 'MinIO Console'
sudo ufw --force enable
sudo ufw status numbered
```

## 15.7 常见问题

### Q1: `docker compose version` 命令找不到?
**A:** Ubuntu 22.04 默认 `docker-compose` (V1) 而不是 `docker compose` (V2 plugin)。执行:
```bash
sudo apt install -y docker-compose-plugin
```

### Q2: 当前用户执行 `docker` 报 "permission denied"?
**A:** docker 组权限仅对**新会话**生效。当前 shell 需:
```bash
newgrp docker
# 或重新登录 SSH
```

### Q3: Elasticsearch 启动报 `max virtual memory areas vm.max_map_count [65530] is too low`?
**A:** 内核参数未生效。执行:
```bash
sudo sysctl -w vm.max_map_count=262144
# 检查持久化
cat /etc/sysctl.d/99-zotprime.conf
```

### Q4: 时区不对,日志时间戳偏差?
**A:** `timedatectl status` 看 NTP synchronized。偏差 >5 秒会导致 dataserver 的 token 过期。
```bash
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd
```

### Q5: swap 关不掉 (`swapoff failed`)?
**A:** 系统正在使用 swap。先看哪些进程占用:
```bash
# 注意: 这里仅用于诊断,生产环境慎重使用
smem -t -p | grep -i swap
# 或
for proc in /proc/[0-9]*; do
    awk '/^Swap:/ { if ($2 > 0) print FILENAME, $2 }' "$proc/smaps" 2>/dev/null
done | sort -k2 -n -r | head
```

### Q6: 防火墙启用后 SSH 断了?
**A:** SSH 22 端口的 allow 规则会先添加,但 UFW 默认 deny 入站。脚本顺序保证先 allow SSH 再 enable,但如果手动操作顺序错误,可能被锁在外面:
- **云服务器:** 通过控制台 VNC 串行控制台登录
- **物理机:** 单用户模式进入

## 15.8 附录 A: PHP 8.5 验证记录

> 来自 PR#0 (feature/dataserver-php85-verify) 验证结果。详见 `docs/technical/php85-verification-report.md`。

| 项 | 结果 |
|----|------|
| alpine 3 仓库 `php85-*` 包 | ✅ 47 个包全部可用 |
| dataserver 镜像构建 | ✅ 36 step, exit 0 |
| PHP 实际版本 | **PHP 8.5.8** |
| 关键扩展 (11 个) | ✅ mysqli / pdo_mysql / redis / memcached / intl / mbstring / curl / openssl / xml / zip |
| 镜像大小 | 781MB |
| 风险 R1 | **已关闭** — 无需回退方案 |

**重新执行验证:**
```bash
./bin/prepare-ubuntu-server.sh --check-php85
```

## 15.9 附录 B: 与其他章节的关系

- **部署 ZotPrime:** 进入 [16-intranet-deployment.md](16-intranet-deployment.md)
- **离线打包客户端:** 进入 [17-intranet-package.md](17-intranet-package.md)
- **Win7 兼容性:** 进入 [18-win7-compatibility.md](18-win7-compatibility.md)
- **运维手册:** 进入 [19-operations-manual.md](19-operations-manual.md)