# ZotPrime 用户手册

**版本:** v3.2.0
**最后更新:** 2026-05-20
**适用范围:** 最终用户（研究人员、学生、教师）、系统管理员

---

## 目录

1. [产品简介](#1-产品简介)
2. [快速开始](#2-快速开始)
3. [部署指南](#3-部署指南)
4. [Zotero 客户端使用](#4-zotero-客户端使用)
5. [Admin 管理面板](#5-admin-管理面板)
6. [Portal 用户门户](#6-portal-用户门户)
7. [用户与组管理](#7-用户与组管理)
8. [客户端构建](#8-客户端构建)
9. [常见问题](#9-常见问题)
10. [附录](#10-附录)

---

## 1. 产品简介

### 1.1 什么是 ZotPrime

ZotPrime 是一个自托管的 Zotero 文献管理服务平台。它允许您在自己的服务器或组织内部网络上部署完整的 Zotero 服务，实现：

- **数据完全自主**：所有文献数据存储在自有服务器，不经过第三方
- **内网可用**：适用于无互联网连接的内网环境
- **团队协作**：多用户共享文献库，支持群组协作
- **完整兼容**：与官方 Zotero 客户端完全兼容

### 1.2 适用场景

| 场景 | 说明 |
|------|------|
| 高校/研究所 | 为全校师生提供统一的文献管理平台 |
| 企业研发 | 在内网环境中管理技术文献和专利 |
| 涉密单位 | 数据不出内网，完全离线部署 |
| 科研团队 | 多人协作共建文献库 |

### 1.3 系统组成

| 组件 | 说明 |
|------|------|
| **数据服务** | 提供 Zotero 客户端连接的后端 API |
| **Admin 管理面板** | Web 界面，管理员管理用户和群组 |
| **Portal 用户门户** | Web 界面，用户自助注册和浏览文献 |
| **Zotero 客户端** | 桌面软件，用于文献管理和阅读 |

---

## 2. 快速开始

### 2.1 硬件要求

| 规模 | CPU | 内存 | 存储 |
|------|-----|------|------|
| 10 人以下 | 2 核 | 4 GB | 50 GB |
| 50 人以下 | 4 核 | 8 GB | 200 GB |
| 100 人以上 | 8 核+ | 16 GB+ | 500 GB+ |

### 2.2 软件要求

- Ubuntu 20.04+ / Debian 11+ / CentOS 8+
- Docker Engine 20.10+
- Docker Compose Plugin

### 2.3 最快部署（5 分钟）

```bash
# 1. 安装 Docker Compose 和依赖
sudo apt update
sudo apt install docker-compose-plugin openssl php-cli

# 2. 下载 ZotPrime
git clone --recursive https://github.com/uniuuu/zotprime.git
cd zotprime

# 3. 一键启动
./bin/install.sh
```

运行 `install.sh` 时，系统会提示您输入服务器 IP 地址。输入完成后，脚本会自动生成密钥并启动所有服务。

### 2.4 验证部署

```bash
# 检查所有服务是否运行
docker compose ps

# 应看到以下服务均为 "running" 状态：
# zotprime-db, zotprime-dataserver, zotprime-elasticsearch,
# zotprime-redis, zotprime-memcached, zotprime-minio 等
```

访问以下地址验证服务：

| 服务 | 地址 |
|------|------|
| Zotero API | `http://<服务器IP>:8080/` |
| Stream Server | `http://<服务器IP>:8081/` |

如果页面正常返回（无报错），说明部署成功。

---

## 3. 部署指南

### 3.1 Docker Compose 部署（推荐）

适用于单机部署，最简单的部署方式。

#### 3.1.1 标准部署

```bash
./bin/install.sh
```

安装脚本会自动：
- 生成所有安全密钥
- 初始化数据库
- 创建存储桶
- 启动全部服务

#### 3.1.2 包含 Admin 管理面板

```bash
docker compose --profile admin up -d
```

访问管理面板：`http://<服务器IP>:8082/login`

#### 3.1.3 包含 Portal 用户门户

```bash
docker compose --profile portal up -d
```

访问用户门户：`http://<服务器IP>:3045/`

#### 3.1.4 全部功能

```bash
docker compose --profile admin --profile portal up -d
```

### 3.2 Kubernetes 部署

适用于生产环境和多节点集群部署。

#### 3.2.1 MicroK8s（本地 K8s）

**第一步：安装 MicroK8s**

```bash
sudo snap install microk8s --classic
sudo usermod -a -G microk8s $USER
```

**第二步：启用必要模块**

```bash
microk8s enable hostpath-storage helm registry dns ingress metallb
```

**第三步：构建镜像**

```bash
cd zotprime/zotprime-k8s/microk8s/scripts
./buildimages.sh
./pushimages.sh
```

**第四步：部署**

```bash
cd ../
kubectl create namespace zotprime
helm install zotprime-k8s helm-chart --namespace zotprime
```

#### 3.2.2 GKE（Google Cloud）

请参考技术手册第 8 章的完整 GKE 部署流程，涉及 Terraform 和 Helm 配置。

### 3.3 服务端口一览

| 服务 | 端口 | 协议 | 说明 |
|------|------|------|------|
| Zotero API | 8080 | HTTP | 客户端连接端点 |
| Stream Server | 8081 | WebSocket | 实时同步通知 |
| Admin 面板 | 8082 | HTTP | Web 管理界面 |
| Portal 门户 | 3045 | HTTP | 用户注册门户 |
| PHPMyAdmin | 8083 | HTTP | 数据库管理 |
| MinIO S3 | 9000 | HTTP | 对象存储 API |
| MinIO Web | 9001 | HTTP | 对象存储管理界面 |

> **注意：** PHPMyAdmin 和 MinIO 建议仅在内网开放，生产环境应配置防火墙规则。

---

## 4. Zotero 客户端使用

### 4.1 下载客户端

有两种方式获取客户端：

**方式一：使用官方客户端**

从 [zotero.org/download](https://www.zotero.org/download/) 下载官方客户端，然后修改同步设置连接到自建服务器。

**方式二：使用定制客户端**

项目提供了预配置服务器地址的定制版客户端，参见 [第 8 章 客户端构建](#8-客户端构建)。

### 4.2 配置同步设置

1. 打开 Zotero 客户端
2. 进入 **编辑 → 首选项**（Mac 上为 **Zotero → 设置**）
3. 切换到 **同步** 标签页
4. 输入您的服务器凭证：
   - **用户名：** 管理员创建的用户名（默认为 `admin`）
   - **密码：** 对应的密码
5. 点击 **设置同步** 旁边的 **高级** 按钮
6. 修改以下地址：
   - **数据同步 URL：** `http://<服务器IP>:8080/`
   - **文件同步 URL：** `http://<服务器IP>:8080/`
7. 保存并重启客户端

### 4.3 配置流式服务器（实时同步）

1. 在 Zotero 中，打开 **工具 → 开发者 → 高级配置编辑器**
2. 搜索 `extensions.zotero.sync.streamServerUrl`
3. 设置为：`ws://<服务器IP>:8081/`

### 4.4 首次使用

1. 打开客户端，点击同步按钮
2. 首次同步会建立本地数据库
3. 添加一篇文献测试：点击 **新建条目** 图标，选择类型并填写信息
4. 再次点击同步，数据将保存到服务器

---

## 5. Admin 管理面板

### 5.1 访问管理面板

浏览器访问：`http://<服务器IP>:8082/login`

### 5.2 首次登录

1. 使用安装脚本生成的凭证登录：
   - **用户名：** `webadmin`（默认）
   - **密码：** 安装脚本输出的 `WEBADMIN_PASSWORD_PLAIN`
2. 登录成功后直接进入管理面板。

> **注意：** 本项目默认**已关闭 2FA 二次验证**，无需手机扫码。如需重新启用，请参考技术手册第 6 章。

### 5.3 管理面板功能

#### 5.3.1 仪表盘

登录后进入仪表盘，显示：
- 用户总数
- 群组总数
- 系统概览

#### 5.3.2 用户管理

- **查看用户列表：** 显示所有用户的用户名、邮箱、状态
- **创建用户：** 填写用户名、邮箱、密码后点击创建
- **启用/禁用用户：** 点击用户旁的操作按钮
- **设置存储配额：** 查看用户的存储使用情况，设置配额上限（MB）
- **删除用户：** 永久删除用户及其数据

#### 5.3.3 群组管理

- **查看群组列表：** 显示所有群组名称、类型、成员数
- **创建群组：** 选择群组类型后创建
  - **PublicOpen（公开开放）：** 任何人都可加入，不支持文件附件
  - **PublicClosed（公开受限）：** 对外可见，需审批加入
  - **Private（私有）：** 仅受邀成员可见
- **添加成员：** 将用户添加到群组，可设置角色（普通成员/管理员）
- **移除成员：** 将用户从群组中移除
- **删除群组：** 永久删除群组

#### 5.3.4 条目管理

- **浏览条目：** 查看所有文献条目
- **发布条目：** 将条目发布到指定群组，供群组成员查看

### 5.4 密码重置

如需重置 Admin 管理面板密码：

```bash
# 生成新的 bcrypt 密码哈希
php -r "echo password_hash('新密码', PASSWORD_BCRYPT, ['cost' => 12]);"

# 将输出结果替换到 .env 文件中的 WEBADMIN_PASSWORD
# 然后重启 Admin 服务
docker compose --profile admin restart admin
```

---

## 6. Portal 用户门户

### 6.1 访问门户

浏览器访问：`http://<服务器IP>:3045/`

### 6.2 注册账号

1. 访问门户首页，点击 **注册**
2. 填写用户名、邮箱、密码
3. 提交注册后，系统会为您创建账号
4. 首次登录可能需要验证邮箱

### 6.3 登录

1. 输入用户名和密码
2. 如果启用了 2FA，输入 Google Authenticator 的验证码
3. 登录成功后进入个人门户页面

### 6.4 门户功能

- **浏览图书馆：** 查看个人和群组图书馆中的文献
- **查看条目详情：** 查看单篇文献的完整元数据
- **搜索：** 通过关键词搜索图书馆

> **提示：** Portal 门户功能目前较为基础。完整的 Web 图书馆管理（创建条目、编辑收藏集、添加注释等）需要通过 Zotero 桌面客户端完成。

---

## 7. 用户与组管理

### 7.1 通过命令行管理

管理员可通过 `bin/admin.sh` 脚本管理用户和群组。

#### 用户操作

```bash
# 创建用户
./bin/admin.sh docker user create 用户名 邮箱 密码
./bin/admin.sh docker user create zhangsan zhangsan@university.edu.cn Pass123456

# 查看所有用户
./bin/admin.sh docker user list

# 查看用户存储配额
./bin/admin.sh docker user quota <用户ID>

# 设置存储配额（单位：MB）
./bin/admin.sh docker user set-quota <用户ID> 2048

# 禁用用户
./bin/admin.sh docker user disable 用户名

# 启用用户
./bin/admin.sh docker user enable 用户名
```

#### 群组操作

```bash
# 创建群组
./bin/admin.sh docker group create 群主用户ID "群组名称" 群组类型
./bin/admin.sh docker group create 1 "计算机科学学院" Private

# 查看所有群组
./bin/admin.sh docker group list

# 添加成员
./bin/admin.sh docker group add-user 群组ID 用户ID 角色
./bin/admin.sh docker group add-user 1 2 member   # 普通成员
./bin/admin.sh docker group add-user 1 3 admin    # 群组管理员

# 查看群组成员
./bin/admin.sh docker group members 群组ID

# 移除成员
./bin/admin.sh docker group remove-user 群组ID 用户ID

# 删除群组
./bin/admin.sh docker group delete 群组ID
```

### 7.2 群组类型说明

| 类型 | 可见性 | 加入方式 | 文件支持 | 适用场景 |
|------|--------|----------|----------|----------|
| PublicOpen | 公开 | 自由加入 | 不支持 | 公开文献列表 |
| PublicClosed | 公开 | 需审批 | 支持 | 课程资料共享 |
| Private | 仅成员 | 邀请制 | 支持 | 科研团队 |

### 7.3 通过 Web 界面管理

Admin 管理面板（`http://<IP>:8082`）提供了与命令行等效的可视化操作界面，操作方式参见 [第 5 章](#5-admin-管理面板)。

---

## 8. 客户端构建

### 8.1 Linux 客户端

```bash
DOCKER_BUILDKIT=1 docker build --progress=plain --file client.Dockerfile \
  --build-arg HOST_DS=http://<服务器IP>:8080/ \
  --build-arg HOST_ST=ws://<服务器IP>:8081/ \
  --build-arg MLW=l --output build .
```

运行：
```bash
./build/staging/Zotero_*/zotero
```

### 8.2 Windows 客户端

```bash
DOCKER_BUILDKIT=1 docker build --progress=plain --file client.Dockerfile \
  --build-arg HOST_DS=http://<服务器IP>:8080/ \
  --build-arg HOST_ST=ws://<服务器IP>:8081/ \
  --build-arg MLW=w --output build .
```

运行：
```bash
./build/staging/Zotero_*/zotero.exe
```

### 8.3 Mac 客户端

```bash
git submodule update --init --recursive
cd client
./config.sh
cd zotero-client
npm install
npm run build
app/scripts/dir_build -p m
```

运行：
```bash
./staging/Zotero_*/zotero
```

### 8.4 使用官方客户端连接

如果不想构建定制客户端，可使用官方 Zotero 客户端：

1. 从 [zotero.org/download](https://www.zotero.org/download/) 下载并安装
2. 打开 **编辑 → 首选项 → 同步**
3. 修改数据同步 URL 为您的服务器地址 `http://<IP>:8080/`
4. 使用管理员创建的账号登录

---

## 9. 常见问题

### 9.1 部署相关

**Q: 安装脚本报 "openssl not found" 错误？**

A: 安装 openssl 和 php-cli：
```bash
sudo apt install openssl php-cli
```

**Q: 服务启动后 dataserver 一直报错？**

A: 查看日志：
```bash
docker compose logs -f dataserver
```
常见原因是数据库初始化未完成，等待 1-2 分钟后重启服务：
```bash
docker compose restart
```

**Q: 如何查看安装脚本生成的密码？**

A: 密码仅在安装时显示一次。如果丢失，可查看 `.env` 文件中的对应变量：
```bash
grep ADMIN_PASSWORD .env
grep WEBADMIN_PASSWORD_PLAIN .env
```

**Q: 可以更换端口吗？**

A: 可以。修改 `docker-compose.yml` 中对应服务的 `ports` 映射即可。

### 9.2 客户端使用相关

**Q: 客户端同步报错 401？**

A: 检查用户名和密码是否正确。密码区分大小写。

**Q: 客户端无法连接流式服务器？**

A: 检查 WebSocket 地址是否正确：`ws://<IP>:8081/`。确保 8081 端口未被防火墙拦截。

**Q: 文件上传失败？**

A: 检查 MinIO 服务是否正常：
```bash
docker compose ps minio
curl http://<IP>:9000/minio/health/live
```

### 9.3 管理相关

**Q: 忘记了 Admin 面板密码怎么办？**

A: 重置密码：
```bash
php -r "echo password_hash('新密码', PASSWORD_BCRYPT, ['cost' => 12]);"
# 将结果写入 .env 的 WEBADMIN_PASSWORD，重启 admin 服务
docker compose --profile admin restart admin
```

**Q: 如何查看某个用户使用了多少存储空间？**

A:
```bash
./bin/admin.sh docker user quota <用户ID>
```

### 9.4 数据安全

**Q: 数据是否加密存储？**

A: 数据库（MariaDB）中的密码使用哈希存储。附件文件以原始格式存储在 MinIO 中。建议在磁盘层面启用加密。

**Q: 如何备份数据？**

A: 参考技术手册第 12 章的备份方案。核心是备份 MariaDB 数据和 MinIO 存储。

**Q: 服务重启会丢失数据吗？**

A: 不会。数据存储在 Docker 数据卷中，容器重启不会丢失数据。但执行 `docker compose down -v` 会删除数据卷。

---

## 10. 附录

### 10.1 默认凭据汇总

| 服务 | 用户名 | 密码 | 备注 |
|------|--------|------|------|
| Zotero API | `admin` | 安装脚本生成 | 首个用户账号 |
| Admin 面板 | `webadmin` | 安装脚本生成 | Web 管理界面 |
| PHPMyAdmin | `root` | `.env` 中查看 | 数据库管理 |
| MinIO Web UI | `zotprimeminio` | `.env` 中查看 | 对象存储管理 |

### 10.2 环境变量参考

| 变量 | 说明 | 示例 |
|------|------|------|
| `SERVER_IP` | 服务器 IP | `192.168.1.100` |
| `VER` | 镜像版本标签 | `v3.2.0` |
| `MARIADB_ROOT_PASSWORD` | 数据库 root 密码 | 自动生成 |
| `API_SUPER_TOKEN` | 管理员 API Token | 自动生成 |
| `ADMIN_USERNAME` | 首个 Zotero 用户名 | `admin` |
| `ADMIN_PASSWORD` | 首个 Zotero 用户密码 | 自动生成 |
| `WEBADMIN_USERNAME` | Admin 面板登录名 | `webadmin` |
| `WEBADMIN_PASSWORD` | Admin 面板密码（bcrypt） | 自动生成 |
| `APP_KEY` | Laravel 应用密钥 | 自动生成 |
| `PORTAL_SESSION_SECRET` | Portal 会话密钥 | 自动生成 |

### 10.3 目录结构

```
zotprime/
├── bin/                          # 管理脚本
│   ├── install.sh                # 安装脚本
│   ├── admin.sh                  # 用户/组管理脚本 (Bash)
│   └── admin.py                  # 用户/组管理脚本 (Python)
├── stack/                        # 各服务配置与源码
│   ├── dataserver/               # Zotero Data Server
│   ├── stream-server/            # WebSocket 流服务
│   ├── admin/                    # Laravel 管理面板
│   ├── webui/                    # Next.js 用户门户
│   └── ...                       # 基础设施服务配置
├── zotprime-k8s/                 # Kubernetes 部署配置
│   ├── microk8s/                 # MicroK8s 配置
│   └── GKE/                      # GKE 配置
├── docs/                         # 文档
│   ├── technical-manual.md       # 技术手册
│   ├── user-manual.md            # 用户手册
│   ├── plan/                     # 规划方案
│   ├── admin.md                  # Admin 面板说明
│   ├── custom-ca-certificate.md  # 自定义 CA 证书
│   └── K8s/                      # K8s 部署文档
├── docker-compose.yml            # Docker Compose 配置
├── .env_example                  # 环境变量模板
└── README.md                     # 项目说明
```

### 10.4 相关文档

| 文档 | 路径 | 说明 |
|------|------|------|
| 技术手册 | `docs/technical-manual.md` | 系统架构、API 参考、运维指南 |
| 差距分析 | `docs/plan/2026-05-20-zotero-gap-analysis.md` | 与官方功能对比与完善方案 |
| Admin 面板说明 | `docs/admin.md` | Admin 面板设置指南 |
| 自定义 CA 证书 | `docs/custom-ca-certificate.md` | 企业网络证书配置 |
| MicroK8s 部署 | `docs/K8s/MICROK8S.md` | K8s 部署详细步骤 |

### 10.5 获取帮助

- **项目主页:** https://github.com/uniuuu/zotprime
- **Issues:** https://github.com/uniuuu/zotprime/issues
- **Zotero 官方文档:** https://www.zotero.org/support/
