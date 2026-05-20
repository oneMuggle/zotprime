# ZotPrime 技术手册

**版本:** v3.2.0
**最后更新:** 2026-05-20
**适用范围:** 运维工程师、系统管理员、二次开发者

---

## 目录

1. [系统架构](#1-系统架构)
2. [服务组件](#2-服务组件)
3. [网络拓扑](#3-网络拓扑)
4. [数据存储](#4-数据存储)
5. [API 接口](#5-api-接口)
6. [认证与安全](#6-认证与安全)
7. [Docker Compose 部署](#7-docker-compose-部署)
8. [Kubernetes 部署](#8-kubernetes-部署)
9. [配置管理](#9-配置管理)
10. [运维管理](#10-运维管理)
11. [监控与日志](#11-监控与日志)
12. [备份与恢复](#12-备份与恢复)
13. [二次开发](#13-二次开发)
14. [故障排查](#14-故障排查)

---

## 1. 系统架构

### 1.1 架构概览

ZotPrime 是一个基于容器化的自托管 Zotero 服务部署平台，由以下层次组成：

```
┌─────────────────────────────────────────────────────────────┐
│                      接入层                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ API :8080│  │WS :8081  │  │MinIO:9000│  │Admin:8082│   │
│  │Portal:3045│ │S3Web:9001│ │PMA :8083 │  │          │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
├─────────────────────────────────────────────────────────────┤
│                      应用层                                  │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐            │
│  │ Dataserver │  │Stream Srv  │  │  Admin     │  Portal    │
│  │(PHP/Apache)│  │ (Node.js) │  │ (Laravel12)│ (Next.js16)│
│  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘  └────┬────┘
│        │               │               │              │     │
├────────┼───────────────┼───────────────┼──────────────┼─────┤
│        ▼               ▼               ▼              ▼     │
│                   基础设施层                                 │
│  ┌────────┐ ┌────────┐ ┌──────┐ ┌──────┐ ┌─────────┐      │
│  │MariaDB │ │Elastic │ │Redis │ │Memc. │ │  MinIO  │      │
│  │        │ │search  │ │      │ │ached │ │  (S3)   │      │
│  └────────┘ └────────┘ └──────┘ └──────┘ └─────────┘      │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 技术栈

| 层次 | 技术 | 说明 |
|------|------|------|
| 数据服务 API | PHP 8.5 + Apache2 + uWSGI + Zend Framework | Zotero Data Server 官方代码 fork |
| 实时同步 | Node.js 22 + WebSocket | 流式推送库变更通知 |
| Web 管理 | Laravel 12 + Blade + Tailwind CSS 4 | 用户/组/配额/条目管理 |
| Web 门户 | Next.js 16 + React 19 + TypeScript | 注册/登录/2FA/条目浏览 |
| 关系数据库 | MariaDB | 用户、组、条目、收藏集等元数据 |
| 搜索引擎 | Elasticsearch (单节点) | 全文搜索 |
| 缓存 | Redis + Memcached | 会话、缓存、通知、限流 |
| 对象存储 | MinIO (S3 兼容) | 附件文件存储 |
| AWS 模拟 | LocalStack | SNS/SQS/API Gateway 模拟 |
| HTML 清洗 | TinyMCE Clean Server | 富文本内容安全过滤 |

---

## 2. 服务组件

### 2.1 核心服务

#### Dataserver (`zotprime-dataserver`)

Zotero 数据服务核心，实现了完整的 Zotero Web API v3 协议。

- **镜像:** `uniuu/zotprime-dataserver:${VER}`
- **端口:** 8080
- **静态 IP:** 10.5.5.8
- **健康检查:** HTTP GET `:8080/`
- **配置文件:** `stack/dataserver/config/config.inc.php`
- **路由文件:** `stack/dataserver/config/routes.inc.php`

**主要功能:**
- 用户和组图书馆 CRUD
- 条目、收藏集、标签、搜索的增删改查
- 文件上传下载（MinIO S3 后端）
- 全文内容索引与检索
- API Key 管理
- 存储配额管理
- Admin 管理接口（需 `API_SUPER_TOKEN`）

**依赖:** MariaDB (10.5.5.2)、Elasticsearch (10.5.5.3)、Redis (10.5.5.4)、Memcached (10.5.5.5)、MinIO (10.5.5.7)、LocalStack (10.5.5.6)、TinyMCE Clean (10.5.5.9)

#### Stream Server (`zotprime-streamserver`)

实时协作通知服务，基于 WebSocket 推送图书馆变更事件。

- **镜像:** `uniuu/zotprime-streamserver:${VER}`
- **端口:** 8081 (WebSocket)
- **静态 IP:** 10.5.5.10
- **健康检查:** HTTP GET `:8081/health`
- **配置:** `stack/stream-server/config/default.js`

```js
{
  httpPort: 8081,
  redis: { url: 'redis://redis:6379' },
  apiURL: 'http://dataserver:8080/',
  apiVersion: 3,
  globalTopics: ['styles', 'translators'],
  keepaliveInterval: 25000
}
```

#### Admin Panel (`zotprime-admin`)

Web 管理界面，提供用户和组的可视化管理。

- **镜像:** `uniuu/zotprime-admin:${VER}`
- **端口:** 8082
- **静态 IP:** 10.5.5.13
- **Profile:** `admin`（需显式启用）
- **框架:** Laravel 12
- **认证:** 用户名/密码 + TOTP 2FA（兼容 Microsoft Authenticator、Authy、FreeOTP 等任意 TOTP 应用）

**主要路由:**

| 路由 | 方法 | 功能 |
|------|------|------|
| `/login` | GET/POST | 登录 |
| `/2fa` | GET/POST | 2FA 验证 |
| `/users` | GET/POST/DELETE | 用户管理 |
| `/groups` | GET/POST/DELETE | 群组管理 |
| `/items` | GET | 条目浏览 |
| `/items/publish` | POST | 条目发布到群组 |

#### Portal (`zotprime-portal`)

用户自助注册和基础图书馆浏览门户。

- **镜像:** `uniuu/zotprime-portal:${VER}`
- **端口:** 3045 (容器内 3000)
- **静态 IP:** 10.5.5.14
- **Profile:** `portal`（需显式启用）
- **框架:** Next.js 16 App Router
- **认证:** iron-session + TOTP 2FA

**API 路由:**

| 路由 | 方法 | 功能 |
|------|------|------|
| `/api/auth/register` | POST | 用户注册 |
| `/api/auth/login` | POST | 用户登录 |
| `/api/auth/logout` | POST | 登出 |
| `/api/auth/verify` | POST | TOTP 验证 |
| `/api/items` | GET | 获取条目列表 |
| `/api/items/[id]` | GET | 获取单个条目 |

### 2.2 基础设施服务

| 服务 | 镜像 | IP | 说明 |
|------|------|----|------|
| MariaDB | `uniuu/zotprime-db:${VER}` | 10.5.5.2 | 5 个数据库（master、shard_1、shard_2、ids、www） |
| Elasticsearch | `uniuu/zotprime-elasticsearch:${VER}` | 10.5.5.3 | 全文搜索，单节点，xpack 安全禁用 |
| Redis | `uniuu/zotprime-redis:${VER}` | 10.5.5.4 | 集群禁用，appendonly 持久化 |
| Memcached | `uniuu/zotprime-memcached:${VER}` | 10.5.5.5 | 2047MB 内存，50M 单项大小 |
| MinIO | `uniuu/zotprime-minio:${VER}` | 10.5.5.7 | S3 兼容存储，2 个 bucket（zotero、zotero-fulltext） |
| LocalStack | `uniuu/zotprime-localstack:${VER}` | 10.5.5.6 | SNS/SQS/API Gateway 模拟 |
| TinyMCE Clean | `uniuu/zotprime-tinymceclean:${VER}` | 10.5.5.9 | HTML 清洗，端口 16342 |
| PHPMyAdmin | `uniuu/zotprime-phpmyadmin:${VER}` | 10.5.5.11 | 数据库管理 UI |

---

## 3. 网络拓扑

### 3.1 Docker 网络

```yaml
networks:
  zotprime:
    driver: bridge
    ipam:
      config:
        - subnet: 10.5.5.0/27
          gateway: 10.5.5.1
```

### 3.2 IP 地址分配

| 服务 | IP |
|------|----|
| 网关 | 10.5.5.1 |
| MariaDB | 10.5.5.2 |
| Elasticsearch | 10.5.5.3 |
| Redis | 10.5.5.4 |
| Memcached | 10.5.5.5 |
| LocalStack | 10.5.5.6 |
| MinIO | 10.5.5.7 |
| Dataserver | 10.5.5.8 |
| TinyMCE Clean | 10.5.5.9 |
| Stream Server | 10.5.5.10 |
| PHPMyAdmin | 10.5.5.11 |
| Init (一次性) | 10.5.5.12 |
| Admin | 10.5.5.13 |
| Portal | 10.5.5.14 |

### 3.3 服务间通信路径

```
Zotero Client → Dataserver (:8080) → MariaDB / Elasticsearch / MinIO
Zotero Client → Stream Server (:8081, WebSocket) → Redis (pub/sub)
Admin Panel → Dataserver API (Bearer Token 认证)
Portal → Dataserver API (MD5 密码比对)
```

---

## 4. 数据存储

### 4.1 数据库架构

Zotero 使用**分片架构**，包含 5 个独立数据库：

```
zotero_master    -- 用户、组、图书馆元数据、分片路由
zotero_shard_1   -- 条目数据分片 1（items、collections、tags）
zotero_shard_2   -- 条目数据分片 2
zotero_ids       -- 全局 ID 生成
zotero_www       -- Web 认证（MD5 密码）、邮箱、用户元数据
```

**www.sql 核心表:**

| 表 | 用途 |
|----|------|
| `users` | Web 用户凭证（MD5 密码哈希） |
| `users_email` | 用户邮箱地址 |
| `users_meta` | 用户元数据（键值对） |
| `storage_institutions` | 机构存储配额 |
| `storage_institution_email` | 机构邮箱映射 |

### 4.2 对象存储 (MinIO)

| Bucket | 用途 |
|--------|------|
| `zotero` | 附件文件（PDF、图片、网页快照等） |
| `zotero-fulltext` | 全文提取内容 |

### 4.3 Redis 用途

| 用途池 | 连接 |
|--------|------|
| 默认缓存 | `redis:6379` (db 0) |
| 请求限流 | `redis:6379` (db 1) |
| 通知队列 | `redis:6379` (db 2) |
| 全文迁移 | `redis:6379` (db 3) |

### 4.4 Memcached 用途

- Dataserver API 响应缓存（JSON、Atom、Bib 格式）
- 请求限流计数

---

## 5. API 接口

### 5.1 核心 API（符合 Zotero Web API v3）

#### 用户级端点

```
GET    /users/{userID}                          用户信息
GET    /users/{userID}/items                    条目列表
GET    /users/{userID}/items/{itemKey}          单个条目
POST   /users/{userID}/items                    创建条目
PUT    /users/{userID}/items/{itemKey}          更新条目
DELETE /users/{userID}/items/{itemKey}          删除条目
GET    /users/{userID}/collections              收藏集列表
GET    /users/{userID}/tags                     标签列表
GET    /users/{userID}/fulltext?since=N         全文增量同步
GET    /users/{userID}/items/{key}/file         文件下载
POST   /users/{userID}/items/{key}/file         文件上传授权
```

#### 群组级端点

```
GET    /groups/{groupID}                        群组信息
GET    /groups/{groupID}/items                  群组条目列表
GET    /groups/{groupID}/users                  群组成员列表
PUT    /groups/{groupID}/users/{userID}         添加群组成员
DELETE /groups/{groupID}/users/{userID}         移除群组成员
```

#### Schema 端点

```
GET    /itemTypes                               条目类型列表
GET    /itemFields                              字段定义
GET    /itemTypeFields?itemType=book            特定类型的字段
GET    /itemTypeCreatorTypes?itemType=book      创作者类型
GET    /creatorFields                           创作者字段定义
GET    /items/new?itemType=book                 新条目模板
```

#### Admin 端点（需 `API_SUPER_TOKEN`）

```
GET    /admin/users                             用户列表
POST   /admin/users                             创建用户
PUT    /admin/users/{id}/status                 启用/禁用用户
DELETE /admin/users/{id}                        删除用户
GET    /admin/groups                            群组列表
GET    /admin/items                             条目列表
GET    /users/{id}/storageadmin                 存储配额查询
POST   /users/{id}/storageadmin                 设置存储配额
```

#### 存储端点

```
GET    /users/{id}/laststoragesync              最后同步时间
POST   /storagepurge                            清除存储
POST   /users/{id}/removestoragefiles           移除存储文件
```

### 5.2 Stream Server API

```
WebSocket ws://{host}:8081/

客户端 → 服务端:
{
  "action": "createSubscriptions",
  "subscriptions": [
    { "apiKey": "...", "topics": ["/users/123", "/groups/456"] }
  ]
}

服务端 → 客户端:
{ "event": "topicUpdated", "topic": "/users/123", "version": 678 }
{ "event": "topicAdded", "apiKey": "...", "topic": "/groups/456" }
{ "event": "topicRemoved", "apiKey": "...", "topic": "/groups/456" }
```

---

## 6. 认证与安全

### 6.1 认证方式

| 组件 | 认证方式 | 凭证存储 |
|------|----------|----------|
| Zotero Client | API Key (Bearer Token) | `users` 表 |
| Admin Panel | 用户名/密码 + TOTP 2FA | `.env` (bcrypt) + SQLite |
| Portal | 用户名/MD5 密码 + TOTP 2FA | `users` 表 (MD5) + SQLite |
| Admin API | Bearer Token (`API_SUPER_TOKEN`) | `.env` (bcrypt hash 验证) |

### 6.2 Admin Panel 认证流程

```
1. 用户提交 username + password → /login
2. 后端比对 WEBADMIN_USERNAME + WEBADMIN_PASSWORD (bcrypt_verify)
3. 通过后跳转到 /2fa
4. 首次登录：生成 TOTP secret → 显示 QR 码 → 用户用任意 TOTP 应用扫码验证
5. 验证通过后标记 2fa_completed，后续登录不再显示 QR 码
6. 登录成功后设置 Laravel session
```

### 6.3 Portal 认证流程

```
1. 用户提交 username + password → /api/auth/login
2. 后端请求 Dataserver /admin/users 获取所有用户
3. 匹配 username，比对 MD5(password) 与存储哈希
4. 如启用 2FA：请求 TOTP 验证码
5. 验证成功后创建 iron-session
6. session 有效期 30 分钟（config.yaml sessionMaxAge: 1800）
```

### 6.4 限流

| 组件 | 规则 |
|------|------|
| Admin Panel | Redis-backed 限流，配置见 config.yaml |
| Portal | 认证 5 次/分钟，浏览 50 次/分钟 |

### 6.5 安全注意事项

- **API_SUPER_TOKEN** 拥有管理员权限，仅保存在 `.env` 中
- MinIO 默认内网访问（10.5.5.7），生产环境需配置访问策略
- PHPMyAdmin 应仅限内网访问
- 生产环境建议配置 TLS（参考 `docs/custom-ca-certificate.md`）

---

## 7. Docker Compose 部署

### 7.1 前置要求

```bash
sudo apt update
sudo apt install docker-compose-plugin openssl php-cli
```

### 7.2 安装步骤

```bash
mkdir -p /opt/zotprime && cd /opt/zotprime
git clone --recursive https://github.com/uniuuu/zotprime.git
cd zotprime
./bin/install.sh
```

安装脚本会：
1. 检查 `openssl` 和 `php-cli` 依赖
2. 复制 `.env_example` 到 `.env`
3. 替换 `SERVER_IP` 为输入的 IP
4. 生成所有随机密钥
5. 执行 `docker compose up -d` 启动全部服务

### 7.3 启动时生成的密钥

| 变量 | 生成方式 | 用途 |
|------|----------|------|
| `MARIADB_ROOT_PASSWORD` | `openssl rand -hex 16` | DB root 密码 |
| `MARIADB_USER` | 固定 `zotprimeprod` | DB 应用用户 |
| `MARIADB_PASSWORD` | `openssl rand -hex 16` | DB 应用用户密码 |
| `MINIOROOTUSER` | 固定 `zotprimeminio` | MinIO 用户 |
| `MINIOROOTPASSWORD` | `openssl rand -hex 16` | MinIO 密码 |
| `API_SUPER_TOKEN` | `openssl rand -hex 32` | Admin API Bearer |
| `API_SUPER_TOKEN_HASH` | PHP `password_hash()` | Admin API 哈希验证 |
| `AUTH_SALT` | `openssl rand -hex 16` | 密码哈希盐 |
| `ADMIN_USERNAME` | 固定 `admin` | 初始 Zotero 用户 |
| `ADMIN_PASSWORD` | `openssl rand -hex 12` | 初始 Zotero 密码（仅显示一次） |
| `WEBADMIN_USERNAME` | 固定 `webadmin` | Admin Panel 登录名 |
| `WEBADMIN_PASSWORD` | PHP `password_hash(..., cost=12)` | Admin Panel 密码哈希 |
| `WEBADMIN_PASSWORD_PLAIN` | `openssl rand -hex 12` | Admin Panel 初始明文密码（仅显示一次） |
| `APP_KEY` | `openssl rand -hex 32` | Laravel 应用密钥 |
| `PORTAL_SESSION_SECRET` | `openssl rand -hex 32` | Portal 会话密钥 |

### 7.4 带 Admin 和 Portal 启动

```bash
docker compose --profile admin --profile portal up -d
```

### 7.5 可用端点

| 服务 | URL | 说明 |
|------|-----|------|
| Zotero API | `http://<IP>:8080/` | 数据服务 API |
| Stream Server | `ws://<IP>:8081/` | WebSocket 实时通知 |
| Admin Panel | `http://<IP>:8082/login` | Web 管理界面 |
| Portal | `http://<IP>:3045/` | 用户注册门户 |
| PHPMyAdmin | `http://<IP>:8083/` | 数据库管理 |
| MinIO S3 | `http://<IP>:9000/` | 对象存储 API |
| MinIO Web UI | `http://<IP>:9001/` | 对象存储管理 |

### 7.6 停止与重启

```bash
# 停止所有服务（保留数据）
docker compose down

# 停止并删除所有数据卷（危险！）
docker compose down -v

# 重启服务
docker compose restart

# 查看日志
docker compose logs -f dataserver
docker compose logs -f admin
```

---

## 8. Kubernetes 部署

### 8.1 MicroK8s 部署

#### 8.1.1 前置要求

```bash
sudo snap install microk8s --classic
sudo usermod -a -G microk8s $USER
sudo chown -f -R $USER ~/.kube

microk8s enable hostpath-storage helm registry dns ingress
microk8s enable metallb:<IP_RANGE>
```

#### 8.1.2 构建与推送镜像

```bash
cd zotprime/zotprime-k8s/microk8s/scripts
./buildimages.sh
./pushimages.sh
```

#### 8.1.3 配置 Helm Values

编辑 `zotprime-k8s/microk8s/helm-chart/values.yaml`：

```yaml
imageRegistry: localhost:32000

ingress:
  hosts:
    api: api.zotprime
    streamserver: stream.zotprime
    minios3Data: s3min.zotprime
    admin: admin.zotprime
    portal: portal.zotprime

persistence:
  dataminio:
    size: 10Gi
  datadb:
    size: 2Gi
  dataredis:
    size: 1Gi
  webadminDb:
    size: 500Mi
  portalData:
    size: 1Gi
```

#### 8.1.4 部署

```bash
kubectl create namespace zotprime
helm install zotprime-k8s helm-chart --namespace zotprime
kubectl get -A cm,secrets,deploy,rs,sts,pod,pvc,svc,ing
```

#### 8.1.5 更新

```bash
cd zotprime/zotprime-k8s/microk8s/scripts
./buildimages.sh
./pushimages.sh
helm upgrade zotprime-k8s helm-chart --namespace zotprime
kubectl rollout restart deployment -n zotprime
```

### 8.2 GKE 部署

#### 8.2.1 前置要求

- Google Cloud SDK
- Terraform
- Kubectl
- Helm

#### 8.2.2 配置 GCP

```bash
gcloud init
gcloud iam service-accounts create zotprimeprod
gcloud projects add-iam-policy-binding <PROJECT_ID> \
  --member="serviceAccount:NAME@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/owner"
```

#### 8.2.3 Terraform 配置

```bash
cd zotprime-k8s/GKE/terraform
gcloud iam service-accounts keys create cred.json \
  --iam-account=NAME@PROJECT_ID.iam.gserviceaccount.com
mv cred.json ./auth/
cp terraform.tfvars_example terraform.tfvars
# 编辑 terraform.tfvars
```

#### 8.2.4 部署

```bash
cd zotprime-k8s/GKE/terraform
terraform init
terraform apply

gcloud container clusters get-credentials zotprime-k8s-prod

cd ..
kubectl create namespace zotprime
helm install zotprime-k8s helm-chart --namespace zotprime
```

#### 8.2.5 配置 DNS

```bash
kubectl get -A ing
# 获取 ADDRESS 列的 IP，配置 A 记录到域名
```

---

## 9. 配置管理

### 9.1 Dataserver 配置

文件: `stack/dataserver/config/config.inc.php`

```php
// 环境变量
$AUTH_SALT         = getenv('AUTH_SALT');
$API_SUPER_TOKEN_HASH = getenv('API_SUPER_TOKEN_HASH');
$AWS_ACCESS_KEY    = getenv('MINIO_ROOT_USER');
$AWS_SECRET_KEY    = getenv('MINIO_ROOT_PASSWORD');

// 服务连接
$S3_ENDPOINT       = 'minio:9000';
$S3_BUCKET         = 'zotero';
$S3_BUCKET_FULLTEXT = 'zotero-fulltext';
$AWS_REGION        = 'us-east-1';
$REDIS_HOSTS       = 'redis:6379';
$MEMCACHED_SERVERS = 'memcached:11211:1';
$SEARCH_HOSTS      = 'elasticsearch';
$HTMLCLEAN_SERVER_URL = 'http://tinymceclean:16342';
```

### 9.2 Admin Panel 配置

文件: `stack/admin/app/config.yaml`

```yaml
dataserver:
  url: http://dataserver:8080
session:
  maxAge: 1800
rateLimit:
  auth: 5/min
  browse: 50/min
```

环境变量:

| 变量 | 说明 |
|------|------|
| `WEBADMIN_USERNAME` | 管理员登录名 |
| `WEBADMIN_PASSWORD` | bcrypt 哈希密码 |
| `API_SUPER_TOKEN` | Dataserver API Bearer Token |
| `APP_KEY` | Laravel 应用密钥 |

### 9.3 Portal 配置

文件: `stack/webui/portal/config.yaml`

```yaml
dataserver:
  url: http://dataserver:8080
session:
  maxAge: 1800
rateLimit:
  auth: 5/min
  browse: 50/min
```

### 9.4 K8s Secret 管理

| K8s Secret | 包含字段 |
|------------|----------|
| `auth-secret` | authSalt, apiSuperToken, apiSuperTokenHash, appKey |
| `db-secret` | mariadbRootPassword, mariadbPassword |
| `minio-secret` | MinIO 密码 |
| `blob-secret` | AWS AccessKeyId, SecretAccessKey |
| `webadmin-secret` | Admin 密码 (bcrypt) |
| `portal-secret` | Portal 会话密钥 |
| `zotero-admin-secret` | 初始 Zotero 用户密码 |

---

## 10. 运维管理

### 10.1 用户管理

```bash
# 创建用户
./bin/admin.sh docker user create alice alice@example.com password123

# 列出所有用户
./bin/admin.sh docker user list

# 查询存储配额
./bin/admin.sh docker user quota <user_id>

# 设置存储配额（MB）
./bin/admin.sh docker user set-quota <user_id> 1024

# 禁用/启用用户
./bin/admin.sh docker user disable alice
./bin/admin.sh docker user enable alice
```

K8s 环境将 `docker` 替换为 `k8s`。

### 10.2 群组管理

```bash
# 创建群组 (PublicOpen / PublicClosed / Private)
./bin/admin.sh docker group create 1 "Research Team" Private

# 列出群组
./bin/admin.sh docker group list

# 删除群组
./bin/admin.sh docker group delete <group_id>

# 添加成员 (member / admin)
./bin/admin.sh docker group add-user 1 2 member

# 移除成员
./bin/admin.sh docker group remove-user 1 2

# 查看群组成员
./bin/admin.sh docker group members 1
```

### 10.3 常用运维命令

```bash
# 查看服务状态
docker compose ps

# 查看特定服务日志
docker compose logs -f --tail=100 dataserver
docker compose logs -f --tail=100 admin
docker compose logs -f --tail=100 streamserver

# 进入容器调试
docker compose exec dataserver bash
docker compose exec admin bash
docker compose exec portal sh

# 查看数据库连接
docker compose exec zotprime-db mysql -u root -p

# 查看 Elasticsearch 健康状态
curl http://10.5.5.3:9200/_cluster/health

# 查看 Redis 状态
docker compose exec redis redis-cli info

# 重启单个服务
docker compose restart dataserver
```

---

## 11. 监控与日志

### 11.1 健康检查端点

| 服务 | 端点 | 方法 |
|------|------|------|
| Dataserver | `GET /` | HTTP 200 |
| Stream Server | `GET /health` | HTTP 200 |
| Elasticsearch | `GET /_cluster/health` | HTTP 200 |
| MariaDB | TCP 3306 | 连接成功 |
| Redis | TCP 6379 | PONG |
| MinIO | `GET /minio/health/live` | HTTP 200 |

### 11.2 日志位置

```bash
# Docker Compose
docker compose logs dataserver
docker compose logs admin
docker compose logs streamserver
docker compose logs elasticsearch

# K8s
kubectl logs -n zotprime deployment/zotprime-dataserver
kubectl logs -n zotprime deployment/zotprime-admin
kubectl logs -n zotprime statefulset/zotprime-elasticsearch
```

### 11.3 关键监控指标

| 指标 | 阈值 | 来源 |
|------|------|------|
| Dataserver 响应时间 | < 500ms | API 日志 |
| Elasticsearch 集群状态 | green | `/_cluster/health` |
| Redis 内存使用 | < 80% | `redis-cli info memory` |
| MariaDB 连接数 | < 80% max_connections | `SHOW STATUS` |
| MinIO 磁盘使用 | < 90% | `mc admin info` |
| Stream Server 连接数 | 监控突增 | 应用日志 |

---

## 12. 备份与恢复

### 12.1 需要备份的数据

| 数据 | 位置 | 备份方式 |
|------|------|----------|
| MariaDB 数据 | `dbdata` 卷 / PVC `datadb` | `mysqldump` 或卷快照 |
| MinIO 数据 | `miniodata` 卷 / PVC `dataminio` | `mc mirror` 或卷快照 |
| Redis 数据 | `dataredis` 卷 / PVC `dataredis` | RDB 快照 |
| .env 文件 | 项目根目录 | 文件备份 |
| Admin SQLite | `admin-data` 卷 | 文件备份 |

### 12.2 Docker Compose 备份

```bash
# 备份数据库
docker compose exec zotprime-db mysqldump \
  -u root -p${MARIADB_ROOT_PASSWORD} \
  --all-databases > backup_$(date +%Y%m%d).sql

# 备份 .env
cp .env .env.backup_$(date +%Y%m%d)

# 备份 MinIO 数据
mc alias set myminio http://localhost:9000 ${MINIOROOTUSER} ${MINIOROOTPASSWORD}
mc mirror myminio/zotero /backup/minio/zotero/$(date +%Y%m%d)/

# 备份数据卷
docker run --rm -v zotprime_dbdata:/data -v $(pwd):/backup \
  alpine tar czf /backup/dbdata_$(date +%Y%m%d).tar.gz -C /data .
```

### 12.3 K8s 备份

```bash
cp values.yaml values_$(date +%Y%m%d).yaml
kubectl get secrets -n zotprime -o yaml > secrets_backup_$(date +%Y%m%d).yaml
kubectl exec -n zotprime statefulset/zotprime-db -- \
  mysqldump -u root -p --all-databases > backup.sql
```

### 12.4 恢复

```bash
# 恢复数据库
docker compose exec -T zotprime-db mysql \
  -u root -p${MARIADB_ROOT_PASSWORD} < backup.sql

# 恢复数据卷
docker run --rm -v zotprime_dbdata:/data -v $(pwd):/backup \
  alpine tar xzf /backup/dbdata_20260520.tar.gz -C /data
```

---

## 13. 二次开发

### 13.1 Dataserver 扩展

```
stack/dataserver/
  config/
    routes.inc.php      # 路由定义
    config.inc.php      # 配置
    ApiController.php   # 基础控制器
  controllers/          # 控制器目录
  models/               # 数据模型
  include/              # 公共库
```

新增 API 端点：在 `routes.inc.php` 添加路由规则，在 `controllers/` 创建对应控制器。

### 13.2 Admin Panel 扩展

```
stack/admin/app/
  app/Http/Controllers/   # 控制器
  routes/web.php          # 路由
  resources/views/        # Blade 模板
  config.yaml             # 配置
```

新增功能：在 `routes/web.php` 添加路由 → 创建控制器 → 创建 Blade 视图。

### 13.3 Portal 扩展

```
stack/webui/portal/
  app/                    # App Router 页面
  app/api/                # API Routes
  components/             # React 组件
  config.yaml             # 配置
```

新增页面：在 `app/` 目录下创建对应路由目录和 `page.tsx`。

### 13.4 构建自定义 Docker 镜像

```bash
# Dataserver
DOCKER_BUILDKIT=1 docker build -f stack/dataserver/ds.Dockerfile \
  -t my-registry/zotprime-dataserver:custom .

# Admin
DOCKER_BUILDKIT=1 docker build -f stack/admin/admin.Dockerfile \
  -t my-registry/zotprime-admin:custom .

# Portal
DOCKER_BUILDKIT=1 docker build -f stack/webui/webui.Dockerfile \
  -t my-registry/zotprime-portal:custom .
```

### 13.5 自定义 CA 证书

```bash
DOCKER_BUILDKIT=1 docker build --progress=plain \
  --file client.Dockerfile \
  --secret id=custom_ca,src=./custom_ca.crt \
  --build-arg HOST_DS=http://<SERVER_IP>:8080/ \
  --build-arg HOST_ST=ws://<SERVER_IP>:8081/ \
  --build-arg MLW=l --output build .
```

---

## 14. 故障排查

### 14.1 服务启动失败

```bash
docker compose ps
docker compose logs <service-name>
```

常见原因：
1. **端口冲突:** `lsof -i :8080`
2. **数据库未就绪:** 等待 init 容器完成
3. **内存不足:** `docker stats`
4. **权限问题:** `sudo chown -R 1000:1000 data/`

### 14.2 数据库初始化失败

```bash
docker compose logs init
docker compose down
docker compose up -d zotprime-db
# 等待 DB 启动完成
docker compose up -d init
docker compose up -d
```

### 14.3 Elasticsearch 相关问题

```bash
sudo sysctl -w vm.max_map_count=262144
curl http://localhost:9200/_cluster/health
```

### 14.4 登录问题

**Admin Panel 密码重置:**

```bash
php -r "echo password_hash('newpassword', PASSWORD_BCRYPT, ['cost' => 12]);"
# 将输出写入 .env 的 WEBADMIN_PASSWORD
```

**Portal 登录:** Portal 使用 MD5 密码比对，需确保 `users` 表中密码哈希正确。

### 14.5 文件上传失败

```bash
# 检查 MinIO 状态
curl http://localhost:9000/minio/health/live

# 创建 bucket
docker compose exec minio mc mb myminio/zotero
docker compose exec minio mc mb myminio/zotero-fulltext
```

### 14.6 常见问题速查

| 问题 | 原因 | 解决 |
|------|------|------|
| Dataserver 500 | MariaDB 未连接 | 检查 DB 服务状态 |
| 搜索无结果 | ES 索引为空 | 等待索引建立或手动触发 |
| 文件无法上传 | MinIO bucket 不存在 | 创建 bucket |
| WebSocket 断连 | Stream Server 未启动 | `docker compose restart streamserver` |
| Admin 403 | API_SUPER_TOKEN 不匹配 | 检查 `.env` 与 dataserver 配置 |
| Portal 页面空白 | Node.js OOM | 增加内存限制或重启 |
| 2FA 验证失败 | 时间不同步 | 确保客户端和服务器时间一致 |
