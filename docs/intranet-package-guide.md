# ZotPrime 内网部署包使用说明

**版本:** v3.2.0
**适用场景:** 通过 U 盘/内网文件共享将完整部署包传输到无互联网连接的服务器

---

## 部署包结构

```
zotprime-intranet-v3.2.0/
├── images/                    # Docker 镜像（13 个 tar 文件）
│   ├── dataserver.tar
│   ├── db.tar
│   ├── elasticsearch.tar
│   ├── redis.tar
│   ├── memcached.tar
│   ├── minio.tar
│   ├── miniomc.tar
│   ├── localstack.tar
│   ├── tinymceclean.tar
│   ├── streamserver.tar
│   ├── phpmyadmin.tar
│   ├── admin.tar
│   └── portal.tar
├── clients/                   # Zotero 桌面客户端安装包（feature/win7-compatibility）
│   ├── win10plus/             # Win10 / Win11 客户端
│   │   ├── Zotero-8.0.1_win-x86_64-setup.exe
│   │   └── SHA256SUMS
│   ├── win7/                  # Win7 / Win8.1 客户端 (5.0.96.3)
│   │   ├── Zotero-5.0.96.3_win-x86_64-setup.exe
│   │   └── SHA256SUMS
│   └── clients-manifest.json  # 客户端清单（含 sha256 + min_os 字段）
├── load-images.sh             # 一键导入镜像脚本
├── bin/                       # 管理脚本
│   ├── deploy-intranet.sh     # 一键部署脚本
│   ├── install.sh             # 基础安装脚本
│   ├── build-local.sh         # 本地构建脚本（备用，含 WIN7=1 Win7 客户端构建）
│   ├── detect-win-version.sh  # 探测 Windows 版本（用于选客户端包）
│   ├── package-for-intranet.sh # 内网部署包打包（含 clients/ 生成）
│   └── admin.sh               # 用户/组管理脚本
├── docs/                      # 完整文档
│   ├── intranet-deployment.md # 内网部署指南（详细版）
│   ├── technical-manual.md    # 技术手册
│   ├── technical/18-win7-compatibility.md # Win7 兼容性技术章节
│   ├── user-manual.md         # 用户手册
│   └── user-manual/10-win7-installation.md # Win7 安装用户章节
├── 内网部署说明.md            # 快速入门（本文件）
├── docker-compose.yml         # Docker Compose 配置
├── .env_example               # 环境变量模板
└── stack/                     # 各服务配置与源码
```

---

## 快速部署（3 步完成）

### 第一步：安装 Docker

如果内网服务器尚未安装 Docker：

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y docker.io docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker

# CentOS/RHEL
curl -fsSL https://get.docker.com | sudo sh
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
```

### 第二步：导入镜像

```bash
cd zotprime-intranet-v3.2.0
./load-images.sh
```

导入完成后验证：

```bash
docker images | grep zotprime
# 应看到 13 个 uniuu/zotprime-* 镜像
```

### 第三步：一键部署

```bash
chmod +x bin/deploy-intranet.sh
./bin/deploy-intranet.sh
```

脚本会提示输入服务器 IP 地址，输入后自动完成配置、启动服务并执行健康检查。

部署完成后屏幕上会显示所有服务的登录凭据，**请务必备份**。

---

## 详细操作

### 验证服务

```bash
# 检查容器状态
docker compose ps

# HTTP 健康检查
curl http://<服务器IP>:8080/        # Zotero API
curl http://<服务器IP>:8082/login   # Admin 面板
curl http://<服务器IP>:9000/minio/health/live  # MinIO
```

### 配置防火墙

```bash
# Ubuntu (UFW)
sudo ufw allow 8080,8081,8082,8083,9000,9001,3045/tcp

# CentOS (firewalld)
sudo firewall-cmd --permanent --add-port=8080-8083/tcp
sudo firewall-cmd --permanent --add-port=9000-9001/tcp
sudo firewall-cmd --permanent --add-port=3045/tcp
sudo firewall-cmd --reload
```

### 用户管理

```bash
# 创建用户
./bin/admin.sh docker user create 用户名 邮箱 密码

# 查看用户
./bin/admin.sh docker user list

# 创建群组
./bin/admin.sh docker group create 群主ID "群组名称" Private
```

### 数据备份

```bash
# 备份数据库
docker compose exec -T zotprime-db mysqldump -u root -p"$MARIADB_ROOT_PASSWORD" --all-databases | gzip > backup.sql.gz

# 备份 .env（含所有密钥）
cp .env .env.backup
```

---

## 常见问题

| 问题 | 解决方法 |
|------|----------|
| Docker 未安装 | 参考第一步安装 Docker |
| 镜像导入失败 | 确保 Docker 服务运行中：`sudo systemctl status docker` |
| Elasticsearch 启动失败 | `sudo sysctl -w vm.max_map_count=262144` |
| 端口冲突 | 修改 `docker-compose.yml` 中的端口映射 |
| 忘记密码 | 查看 `.env` 文件中对应变量 |
| 容器一直 starting | 数据库初始化需要 1-3 分钟，属正常现象 |

---

## 服务端口一览

| 端口 | 服务 | 说明 |
|------|------|------|
| 8080 | Zotero API | 客户端连接端点 |
| 8081 | Stream Server | WebSocket 实时同步 |
| 8082 | Admin 面板 | Web 管理界面 |
| 8083 | PHPMyAdmin | 数据库管理 |
| 9000 | MinIO API | 对象存储 API |
| 9001 | MinIO Web | 对象存储管理界面 |
| 3045 | Portal | 用户注册门户 |

---

## 更多文档

- **内网部署详细指南:** `docs/intranet-deployment.md`
- **技术手册:** `docs/technical-manual.md`
- **用户手册:** `docs/user-manual.md`
