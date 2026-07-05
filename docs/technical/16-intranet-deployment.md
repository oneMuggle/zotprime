# 16. 内网部署 (13 服务 Docker Compose)

> 面向系统管理员。介绍 ZotPrime 13 个 Docker 服务的镜像清单、部署方式、健康检查与故障排查。

---

## 16.1 服务架构总览

ZotPrime 由 13 个 Docker 服务构成,在 `10.5.5.0/27` Docker bridge 网络内互通:

```
                    内网客户端浏览器 / Zotero 桌面客户端
                                   │
        ┌──────────────────────────┼──────────────────────────┐
        │                          │                          │
        ▼                          ▼                          ▼
   8080 Zotero API          8081 Stream (WS)         8082/3045/8083/9001 管理面板
   (dataserver)             (streamserver)           (admin/portal/phpmyadmin/minio)
        │                          │                          │
        └────────────┬─────────────┴────────────┬─────────────┘
                     │                          │
   ┌─────────────────▼──────────┐  ┌────────────▼────────────┐
   │  dataserver (PHP 8.5 +     │  │  streamserver (Node.js) │
   │  Apache, alpine:3)         │  │  tinymceclean (Python)  │
   │  image: uniuu/zotprime-    │  │  admin (Laravel)        │
   │  dataserver:${VER}         │  │  portal (Node.js)       │
   └────────────────────────────┘  └─────────────────────────┘
                     │
   ┌─────────────────▼────────────── 基础服务层 ──────────────────────────┐
   │  db (MariaDB)    │ es (Elasticsearch)  │ redis  │ memcached        │
   │  minio + miniomc │ localstack           │  phpmyadmin (UI)        │
   └─────────────────────────────────────────────────────────────────────┘
                     │
        持久卷: dbdata, miniodata, admin-data
```

## 16.2 13 镜像清单

| # | 服务 | 镜像 | Tag | Dockerfile | 大小 (v3.2.0) |
|---|------|------|-----|-----------|---------------|
| 1 | dataserver | `uniuu/zotprime-dataserver` | `${VER}` | `stack/dataserver/ds.Dockerfile` | 781MB |
| 2 | db | `uniuu/zotprime-db` | `${VER}` | `stack/db/db.Dockerfile` | 472MB |
| 3 | elasticsearch | `uniuu/zotprime-elasticsearch` | `${VER}` | `stack/elasticsearch/es.Dockerfile` | 2.15GB |
| 4 | redis | `uniuu/zotprime-redis` | `${VER}` | `stack/redis/r.Dockerfile` | 57MB |
| 5 | memcached | `uniuu/zotprime-memcached` | `${VER}` | `stack/memcached/m.Dockerfile` | 20MB |
| 6 | minio | `uniuu/zotprime-minio` | `${VER}` | `stack/minio/minio.Dockerfile` | 241MB |
| 7 | miniomc | `uniuu/zotprime-miniomc` | `${VER}` | `stack/minio/miniomc.Dockerfile` | 117MB |
| 8 | localstack | `uniuu/zotprime-localstack` | `${VER}` | `stack/localstack/ls.Dockerfile` | 2.62GB |
| 9 | tinymceclean | `uniuu/zotprime-tinymceclean` | `${VER}` | `stack/tinymce-clean-server/tmcs.Dockerfile` | 271MB |
| 10 | streamserver | `uniuu/zotprime-streamserver` | `${VER}` | `stack/stream-server/sts.Dockerfile` | 346MB |
| 11 | phpmyadmin | `uniuu/zotprime-phpmyadmin` | `${VER}` | `stack/phpmyadmin/pa.Dockerfile` | 1.09GB |
| 12 | admin | `uniuu/zotprime-admin` | `${VER}` | `stack/admin/admin.Dockerfile` | 808MB |
| 13 | portal | `uniuu/zotprime-portal` | `${VER}` | `stack/webui/webui.Dockerfile` | 327MB |
| | | | | **总计** | **~9.9GB** |

> **镜像大小说明:** localstack 和 elasticsearch 是大头(>2GB each),dataserver/admin 是中等(~800MB),基础服务(redis/memcached)很小。完整离线包预计 **~9-10GB**,建议用 16GB+ U 盘。

## 16.3 部署方式

### 16.3.1 方式 A: 一键脚本 (推荐)

```bash
cd /home/fz/project/zotprime

# 联网: 从 Docker Hub 拉取
./bin/deploy-intranet.sh
# 选 y (拉取) 或 n (本地构建)

# 离线: 强制本地构建
MODE=build ./bin/deploy-intranet.sh
```

脚本会自动:
1. 检测/安装 Docker
2. 拉取或构建镜像
3. 生成 `.env` (含随机密码)
4. 启动服务 + 健康检查
5. 打印登录凭据

### 16.3.2 方式 B: 离线包部署

```bash
# 在能上网的机器上打包
./bin/package-for-intranet.sh
# 产出: build/zotprime-intranet-v3.2.0.tar.gz (~9-10GB)

# 在内网服务器上
tar xzf zotprime-intranet-v3.2.0.tar.gz
cd zotprime-intranet-v3.2.0
./load-images.sh                  # 导入 13 镜像
./bin/deploy-intranet.sh          # 一键部署
```

### 16.3.3 方式 C: 手动 docker compose

```bash
cd /home/fz/project/zotprime
cp .env_example .env
# 编辑 .env 填入 SERVER_IP 等参数

# 默认 profile (dataserver + 基础服务 + admin + portal)
docker compose up -d

# 单独启用 admin / portal
docker compose --profile admin up -d
docker compose --profile portal up -d
```

## 16.4 服务依赖关系

启动顺序 (由 docker-compose `depends_on` + `healthcheck` 控制):

```
db (MariaDB) ────┐
                 │
elasticsearch ───┼──► dataserver ──► init (一次性)
                 │
redis ───────────┤
                 │
memcached ───────┤
                 │
minio ───────────┘
                 │
localstack ──────┘ (独立,SNS/SQS)

tinymceclean ──► streamserver ──► dataserver

admin ──► dataserver
portal ──► dataserver
phpmyadmin ──► db (link as mariadb)
```

## 16.5 健康检查

部署脚本自动跑 6 端口 HTTP probe:

| 端口 | 服务 | 期望 HTTP 状态 |
|------|------|----------------|
| 8080 | Zotero API (dataserver) | 200 |
| 8081 | Stream Server | 200 |
| 8082 | Admin Panel | 200 |
| 3045 | Portal | 200 |
| 8083 | PHPMyAdmin | 200 |
| 9000 | MinIO | 200 (`/minio/health/live`) |

**手动健康检查:**

```bash
docker compose ps              # 容器状态
docker compose logs dataserver # 单独服务日志

# curl 各端口
curl -f http://localhost:8080/ && echo "✓ dataserver OK"
curl -f http://localhost:8081/ && echo "✓ streamserver OK"

# 容器内 PHP 版本
docker exec zotprime-zotprime-dataserver-1 php -v | head -1
```

## 16.6 镜像构建链路验证 (PR#2)

### 16.6.1 验证方法

```bash
# 在联网开发机上 (Docker 29.6.1)
cd /home/fz/project/zotprime

# 一次性构建 13 镜像
IMAGE_TAG=v3.2.0 ./bin/build-local.sh

# 验证产物
docker images | grep "uniuu/zotprime.*v3.2.0" | wc -l
# 期望: 13
```

### 16.6.2 实测结果 (2026-07-05)

| # | 镜像 | 大小 | 状态 |
|---|------|------|------|
| 1 | dataserver | 781MB | OK |
| 2 | db | 472MB | OK |
| 3 | elasticsearch | 2.15GB | OK |
| 4 | redis | 57MB | OK |
| 5 | memcached | 20MB | OK |
| 6 | minio | 241MB | OK |
| 7 | miniomc | 117MB | OK |
| 8 | localstack | 2.62GB | OK |
| 9 | tinymceclean | 271MB | OK |
| 10 | streamserver | 346MB | OK |
| 11 | phpmyadmin | 1.09GB | OK |
| 12 | admin | 808MB | OK |
| 13 | portal | 327MB | OK |
| | **总计** | **~9.9GB** | **13/13 OK** |

### 16.6.3 CI Smoke Test (push-all-images.yml)

推送所有镜像后,新增 `smoke-test` job 验证:

1. **PHP 8.5 验证**: 从 dataserver 镜像提取 `/usr/bin/php85` 运行 `php -v`,断言包含 `PHP 8.5`
2. **Manifest amd64 验证**: 用 `docker buildx imagetools inspect` 检查 dataserver manifest 含 `linux/amd64`
3. **全 13 镜像清单验证**: 逐个 inspect 13 个镜像,任何一个 missing 则 exit 1

任何 smoke test 失败 → 整个 workflow 标红,阻止 tag 发布。

## 16.7 服务端口与环境变量

### 16.7.1 端口映射

| 服务 | 容器内端口 | 宿主机端口 | 来源 env |
|------|-----------|-----------|----------|
| zotprime-db | 3306 | (内部) | - |
| zotprime-elasticsearch | 9200 | (内部) | - |
| zotprime-redis | 6379 | (内部) | - |
| zotprime-memcached | 11211 | (内部) | - |
| zotprime-localstack | 4566 | (内部) | - |
| zotprime-minio | 9000, 9001 | **9000, 9001** | - |
| zotprime-dataserver | 8080 | **8080** | - |
| zotprime-tinymceclean | (无) | (内部) | - |
| zotprime-streamserver | 8081 | **8081** | - |
| zotprime-phpmyadmin | 80 | **8083** | - |
| zotprime-init | (无) | (一次性) | - |
| zotprime-admin | 8080 | **8082** | - |
| zotprime-portal | 3000 | **3045** | - |

### 16.7.2 关键环境变量

`.env` 文件 (由 `bin/deploy-intranet.sh` 自动生成):

| 变量 | 用途 |
|------|------|
| `SERVER_IP` | 服务器 IP,客户端连接用 |
| `VER` | 镜像 tag (如 `v3.2.0`) |
| `MARIADB_ROOT_PASSWORD` | DB root 密码 |
| `MARIADB_USER` / `MARIADB_PASSWORD` | DB 应用账号 |
| `MINIOROOTUSER` / `MINIOROOTPASSWORD` | MinIO root 凭据 |
| `API_SUPER_TOKEN` / `API_SUPER_TOKEN_HASH` | Admin API 超级令牌 |
| `AUTH_SALT` | Legacy 密码哈希盐 |
| `ADMIN_USERNAME` / `ADMIN_PASSWORD` | Zotero 初始 admin |
| `WEBADMIN_USERNAME` / `WEBADMIN_PASSWORD` | Admin Panel 账号 |
| `APP_KEY` | Laravel 应用密钥 |
| `PORTAL_SESSION_SECRET` | Portal session 加密密钥 |
| `SECURE_COOKIES` | Portal 是否强制 HTTPS cookie |

> **生产环境:** 部署后请立刻 `cp .env .env.backup` 离线保存,丢失后无法恢复用户密码。

## 16.8 升级流程

```bash
# 1. 备份
cp .env .env.backup
docker compose exec -T db mysqldump -uroot -p"$MARIADB_ROOT_PASSWORD" zotprimeprod > backup-$(date +%Y%m%d).sql

# 2. 拉取新镜像
NEW_VER=v3.3.0
sed -i "s/^VER=.*/VER=$NEW_VER/" .env
docker compose pull

# 3. 滚动重启
docker compose up -d

# 4. 健康检查
sleep 30
./bin/deploy-intranet.sh  # 仅跑健康检查部分
```

## 16.9 常见问题

### Q1: Elasticsearch 起不来,日志报 `max_map_count`?
**A:** 内核参数未生效。详见 [15-ubuntu-server-setup.md §15.7 Q3](15-ubuntu-server-setup.md#q3-elasticsearch-启动报-max-virtual-memory-areas-vmmax_map_count-65530-is-too-low)。

### Q2: dataserver 报 `Connection refused` 到 db?
**A:** db 还在初始化。检查 `docker compose ps` 看 db 是否 healthy (`healthcheck` 通过 `mariadb-admin ping`)。
```bash
docker compose logs db
```

### Q3: 客户端连不上 dataserver?
**A:** 检查 `SERVER_IP` 是否填了内网 IP,客户端的 `extensions.zotero.sync.serverURL` (或 Win7 的 C 路径注入) 是否一致。

### Q4: MinIO bucket 自动创建失败?
**A:** 看 `zotprime-init` 容器日志:
```bash
docker compose logs zotprime-init
```
通常原因是 MinIO root 凭据与 `.env` 中 `MINIOROOTUSER`/`MINIOROOTPASSWORD` 不一致。

### Q5: 升级到新 VER 后,客户端报 "library version mismatch"?
**A:** 这是预期 — 客户端需要重置本地库并重新全量同步:
1. 客户端退出
2. 删除 `~/Zotero/storage` 整个目录
3. 重新启动 Zotero → 全量下载

## 16.10 与其他章节的关系

- **前置:** [15-ubuntu-server-setup.md](15-ubuntu-server-setup.md) — Docker/防火墙/内核参数
- **离线打包:** [17-intranet-package.md](17-intranet-package.md) — docker save 导出
- **客户端:** [18-win7-compatibility.md](18-win7-compatibility.md) — Win7 装机 + PowerShell 注入
- **运维:** [19-operations-manual.md](19-operations-manual.md) — 备份/恢复/监控/故障排查

## 16.11 客户端 IP 注入机制 (PR#3)

> 客户端连接服务端有**两条路径**,分别对应 Win10+ 与 Win7 客户端。详见 [18-win7-compatibility.md](18-win7-compatibility.md) 的 Win7 兜底说明。

### 16.11.1 Win10+ 8.0.1 — 构建期注入

使用 `client.Dockerfile` (3-stage) 进行**完整的** Zotero Windows 客户端构建:

| Stage | 工作 |
|-------|------|
| stage-1 | 修改 `client/zotero-client/resource/config.mjs` 中的 `api.zotero.org` 和 `stream.zotero.org` URL |
| stage-2 | `npm run build` + `app/scripts/dir_build -p w` 产出 Windows 安装包 |
| export-stage | 输出 `app/staging/Zotero-8.0.1_win-x86_64-setup.exe` |

**关键 build args:**

```bash
HOST_DS="http://192.168.1.100:8080/"   # dataserver URL
HOST_ST="ws://192.168.1.100:8081/"     # stream server URL
MLW="w"                                # 平台:w=Windows, l=Linux
```

**自动从 `.env` 读 SERVER_IP**:

`bin/build-local.sh` 默认从 `.env` 的 `SERVER_IP` 行提取,缺省 `127.0.0.1`(本地测试用):

```bash
# 1. 标准用法 — 从 .env 读 SERVER_IP
./bin/build-local.sh

# 2. 自定义 SERVER_IP (覆盖 .env)
SERVER_IP=10.0.0.5 ./bin/build-local.sh

# 3. 完全自定义 URL (覆盖 SERVER_IP)
HOST_DS=http://10.0.0.5:8080/ HOST_ST=ws://10.0.0.5:8081/ ./bin/build-local.sh
```

**产出位置:**

```
dist/win10plus/Zotero-8.0.1_win-x86_64-setup.exe
```

### 16.11.2 Win7 5.0.96.3 — 安装后 PowerShell 注入 (A' 路径 deferred)

5.0.96.3 时代的 setup.exe 是**骨架**(只含 Mozilla runtime + OpenOffice 集成),**主 Zotero XPI 不在 setup.exe 内**,因此 spec 描述的 "解 setup.exe → 改 XPI → 重打包" 的 A' 路径**在 5.0 时代不可行**。

**当前实际做法:**
1. `prebuild_client_win7.Dockerfile` 下载官方 5.0.96.3 setup.exe → 验证 → 重新打包输出
2. 用户装机后,由 IT 在该机器跑 `bin/set-zotero-dataserver.ps1` 做 dataserver URL 注入(C 路径)

**PowerShell 注入脚本功能 (`bin/set-zotero-dataserver.ps1`):**
- 检查 PowerShell 版本(< 5.0 报错引导装 WMF 5.1)
- 多路径候选定位 `zotero@chnm.org.xpi`
- 备份原 XPI (`.bak.yyyyMMddHHmmss`)
- 用 `System.IO.Compression` 解压 → 改 `resource/config.js` → 重打包
- 替换 `https://api.zotero.org` → `$DataServerUrl`
- 替换 `wss://stream.zotero.org` → `$StreamServerUrl`

**用法:**
```powershell
cd C:\path\to\setup\folder
.\set-zotero-dataserver.ps1 `
    -DataServerUrl "http://192.168.1.100:8080/" `
    -StreamServerUrl "ws://192.168.1.100:8081/"
```

### 16.11.3 限制与权衡

| 限制 | 影响 | 缓解 |
|------|------|------|
| Win10+ IP 在构建期硬编码 | IP 改一次要重新 build EXE | 单机构场景够用;多机构需分别 build |
| Win7 装机需 IT 跑一次 PS | 用户不能零接触部署 | 文档明确告知用户;IT 装机 runbook |
| Win10+ `client.Dockerfile` 需 `client/zotero-client` 子模块 | 完整 build 10-20 分钟 | 本地开发可接受;CI 上跑就行 |

### 16.11.4 PR#3 实测结果 (2026-07-05)

**Win7 客户端构建:**

```bash
$ WIN7=1 ./bin/build-local.sh
# ... [14/14] client (Win7 5.0.96.3)
$ ls dist/win7/
Zotero-5.0.96.3_win-x86_64-setup.exe      43466024 bytes
Zotero-5.0.96.3_win-x86_64-setup.exe.sha256

$ sha256sum dist/win7/Zotero-5.0.96.3_win-x86_64-setup.exe
0e38eafce391f944784574a360db9902ac10f9630bcc2e21b114ede7ca32fc51
```

构建时间:**~10 秒**(只下载 + 解压 + 重打包,不改 XPI)

**Win10+ 客户端构建:**

```bash
$ ./bin/build-local.sh
# ... [14/14] client (Win10+ 8.0.1, build-time URL injection)
$ ls dist/win10plus/
Zotero-8.0.1_win-x86_64-setup.exe       # 由 client.Dockerfile (3-stage) 产出
```

构建时间:**~10-20 分钟**(完整 npm build + dir_build -p w)

> **未在本次 PR 实测的原因:** `client.Dockerfile` 需要 `client/zotero-client` 子模块全量 `npm i`,受限于本会话时长。建议在 PR#6 (E2E 验证) 中实测完整链路。

### 16.11.5 已知问题

`stack/admin/admin.Dockerfile` 第 8 行的 `pecl install yaml` 偶发 PECL registry 503 错误("No releases available")。症状:`WIN7=1` 完整链路构建时,admin 阶段失败。已观察到的缓解:
- 重试通常成功(registry 暂态问题)
- 备用方案:`pecl install yaml-2.2.4`(锁定版本)