# 20. 管理员速查 (系统管理员)

> 系统管理员日常运维速查手册:用户/组管理、API token、客户端分发、备份升级。

## 20.1 服务地址

部署后(由 `bin/deploy-intranet.sh` 输出):

| 服务 | URL | 用途 |
|------|-----|------|
| Zotero API | `http://<SERVER_IP>:8080/` | 客户端连接 |
| Stream (WS) | `ws://<SERVER_IP>:8081/` | 实时同步 |
| Admin 面板 | `http://<SERVER_IP>:8082/login` | 用户/组/条目管理 |
| Portal | `http://<SERVER_IP>:3045/` | 用户浏览入口 |
| PHPMyAdmin | `http://<SERVER_IP>:8083/` | 数据库管理 |
| MinIO Web UI | `http://<SERVER_IP>:9001/` | 对象存储管理 |
| 客户端 HTTP | `http://<SERVER_IP>:8000/` | 客户端分发 (PR#4) |

**重要:** MinIO 9000/9001 仅限内网 IP 段访问,严禁对公网开放。

## 20.2 登录凭据

部署时由脚本生成,屏幕输出:

```
Zotero 客户端:
  用户名: admin
  密码:   <随机>

Admin 管理面板 (http://<SERVER_IP>:8082/login):
  用户名: webadmin
  密码:   <随机>

MinIO Web UI (http://<SERVER_IP>:9001/):
  用户名: zotprimeminio
  密码:   <随机>

PHPMyAdmin (http://<SERVER_IP>:8083/):
  用户名: root
  密码:   <MARIADB_ROOT_PASSWORD>
```

> ⚠️ **必须保存 .env 文件!** 丢失后无法恢复密码。
> ```bash
> cp .env .env.backup
> ```

## 20.3 用户管理 (CLI)

通过 `bin/admin.sh` 管理:

```bash
# 列出所有用户
./bin/admin.sh docker user list

# 创建用户
./bin/admin.sh docker user create zhangsan zhangsan@univ.edu.cn Pass123456

# 设置配额 (MB)
./bin/admin.sh docker user set-quota 1 2048

# 禁用用户
./bin/admin.sh docker user disable zhangsan

# 启用用户
./bin/admin.sh docker user enable zhangsan

# 删除用户
./bin/admin.sh docker user delete zhangsan
```

## 20.4 群组管理 (CLI)

```bash
# 列出所有群组
./bin/admin.sh docker group list

# 创建群组
./bin/admin.sh docker group create 1 "Research Team" Private
# 参数: ownerID name type(PublicOpen/PublicClosed/Private)

# 添加成员
./bin/admin.sh docker group add-user 1 2 admin
# 参数: groupID userID role(owner/admin/member)

# 查看成员
./bin/admin.sh docker group members 1

# 移除成员
./bin/admin.sh docker group remove-user 1 2

# 删除群组
./bin/admin.sh docker group delete 1
```

## 20.5 Admin Panel 操作

访问 `http://<SERVER_IP>:8082/login`,登录 webadmin 账号:

- **Dashboard:** 用户/组总数
- **Users:** 用户列表、创建、删除、启用/禁用、配额
- **Groups:** 群组列表、创建、删除、成员管理
- **Items:** 条目浏览、发布到群组

## 20.6 存储配额

```bash
# 设置用户配额
./bin/admin.sh docker user set-quota 1 2048  # 2GB

# 查看配额
./bin/admin.sh docker user quota-info 1

# 通过 API
curl -H "Authorization: Bearer $API_SUPER_TOKEN" \
    http://localhost:8080/users/1/storageadmin
```

## 20.7 API Token

API Super Token 用于 admin CLI 和 REST API 调用:

```bash
# 查看
cat .env | grep API_SUPER_TOKEN

# 重置 (破坏性!所有 admin CLI 调用需更新)
# 1. 生成新 token
NEW_TOKEN=$(openssl rand -hex 32)
NEW_HASH=$(php -r "echo password_hash('$NEW_TOKEN', PASSWORD_BCRYPT);")
# 2. 更新 .env
sed -i "s/^API_SUPER_TOKEN=.*/API_SUPER_TOKEN=$NEW_TOKEN/" .env
sed -i "s/^API_SUPER_TOKEN_HASH=.*/API_SUPER_TOKEN_HASH=$NEW_HASH/" .env
# 3. 重启 dataserver + admin
docker compose up -d
```

## 20.8 客户端分发

详见 [30-distribution.md](30-distribution.md)。

### 20.8.1 快速启动 HTTP 服务器

```bash
./bin/serve-clients.sh
# → http://<SERVER_IP>:8000/
```

### 20.8.2 同步到 SMB

```bash
./bin/sync-clients-to-smb.sh /srv/samba/zotprime/clients
```

### 20.8.3 构建 U 盘

```bash
./bin/build-usb-package.sh /tmp/ZotPrime-Setup-USB
```

## 20.9 数据备份

```bash
# 数据库
docker compose exec -T db \
    mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" zotprimeprod \
    > backup-$(date +%Y%m%d).sql

# MinIO 文件
docker run --rm --network zotprime_zotprime \
    -v /backup/minio:/backup \
    minio/mc mirror --quiet \
    http://minio:9000/zotero-storage /backup/zotero-storage

# 配置
cp .env .env.backup-$(date +%Y%m%d)
chmod 600 .env.backup-*
```

详见 [技术手册 §19.2](../technical/19-operations-manual.md)。

## 20.10 升级流程

```bash
# 1. 备份
cp .env .env.backup
docker compose exec -T db mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" zotprimeprod > backup-pre-upgrade.sql

# 2. 升级 VER
sed -i "s/^VER=.*/VER=v3.3.0/" .env

# 3. 拉新镜像
docker compose pull

# 4. 重启
docker compose up -d

# 5. 健康检查
sleep 30
curl -f http://localhost:8080/ && echo "✓"
```

详见 [技术手册 §19.3](../technical/19-operations-manual.md)。

## 20.11 故障排查速查

| 症状 | 看哪里 |
|------|--------|
| 服务起不来 | `docker compose logs <service>` |
| 端口 8080 不通 | `sudo ufw status` |
| ES 内存满 | `docker stats zotprime-elasticsearch` |
| 数据库死锁 | `docker compose exec db mariadb -e "SHOW PROCESSLIST"` |
| 客户端 sync 失败 | 客户端 → Preferences → Sync → 看错误码 |
| 附件上传失败 | MinIO:9001 → 看 bucket |

详见 [技术手册 §19.6](../technical/19-operations-manual.md) 完整速查表。

## 20.12 常用命令

```bash
# 状态
docker compose ps
docker stats

# 日志
docker compose logs -f <service>

# 重启单服务
docker compose restart <service>

# 进入容器
docker compose exec <service> bash
docker compose exec db mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" zotprimeprod

# 资源清理
docker system prune -a   # 警告:删未用镜像

# 用户管理
./bin/admin.sh docker user list
./bin/admin.sh docker user create <name> <email> <password>
```

## 20.13 下一步

- [00-quickstart.md](00-quickstart.md) - 普通用户快速上手
- [10-win7-installation.md](10-win7-installation.md) - Win7 用户
- [30-distribution.md](30-distribution.md) - 客户端分发三种方式
- [技术手册 §19](../technical/19-operations-manual.md) - 完整运维手册