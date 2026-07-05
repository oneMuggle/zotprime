# 19. 运维手册

> 面向系统管理员。ZotPrime 部署后日常运维:日志查看、数据备份、版本升级、灾备恢复、监控告警、故障排查速查。

---

## 19.1 日志管理

### 19.1.1 容器日志

```bash
# 所有服务
docker compose logs -f --tail=100

# 单个服务
docker compose logs -f dataserver
docker compose logs -f db

# 最近 1 小时
docker compose logs --since="1h" dataserver
```

### 19.1.2 日志位置

容器内日志路径:
| 服务 | 路径 |
|------|------|
| dataserver | Apache access/error → docker logs (stdout/stderr) |
| db | MariaDB binlog + docker logs |
| minio | `/data/.minio/` + docker logs |
| elasticsearch | `/usr/share/elasticsearch/logs/` |
| admin (Laravel) | `storage/logs/laravel.log` |

### 19.1.3 日志轮转

容器日志默认不轮转,可能撑爆磁盘。配置 `/etc/docker/daemon.json`:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "5"
  }
}
```

```bash
sudo systemctl restart docker
docker compose up -d  # 重启服务应用新配置
```

### 19.1.4 关键日志关键字

| 关键字 | 含义 |
|--------|------|
| `OOMKilled` | 容器 OOM,需扩容内存 |
| `Connection refused` | 上游服务未就绪 |
| `permission denied` | 文件权限问题 |
| `503 Service Unavailable` | 临时过载 |
| `library version mismatch` | 客户端/服务端版本不一致 |

## 19.2 数据备份

### 19.2.1 数据库备份 (MariaDB)

```bash
# 完整备份
docker compose exec -T db \
    mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" zotprimeprod \
    > backup-$(date +%Y%m%d).sql

# 压缩
gzip backup-$(date +%Y%m%d).sql
```

### 19.2.2 MinIO 文件备份

```bash
# 用 mc (MinIO Client) mirror
docker run --rm --network zotprime_zotprime \
    -v /backup/minio:/backup \
    minio/mc mirror \
    --quiet \
    http://minio:9000/zotero-storage /backup/zotero-storage
```

### 19.2.3 配置备份

```bash
# .env 必须备份,丢失后无法恢复密码
cp .env .env.backup-$(date +%Y%m%d)
chmod 600 .env.backup-*

# docker-compose.yml (如果修改过)
cp docker-compose.yml docker-compose.yml.backup
```

### 19.2.4 备份脚本 (`bin/backup.sh`)

计划中的备份脚本(本章节留作后续 PR)。当前手动跑上面三条命令。

### 19.2.5 自动备份(crontab)

```bash
# 编辑 crontab
sudo crontab -e

# 每天凌晨 3 点备份
0 3 * * * /home/fz/project/zotprime/bin/backup.sh 2>&1 | logger -t zotprime-backup
```

## 19.3 版本升级

### 19.3.1 升级流程

```bash
# 1. 备份 (必须)
cp .env .env.backup
docker compose exec -T db mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" zotprimeprod > backup-pre-upgrade.sql

# 2. 修改 VER
NEW_VER="v3.3.0"
sed -i "s/^VER=.*/VER=$NEW_VER/" .env

# 3. 拉取新镜像
docker compose pull

# 4. 滚动重启 (depends_on 保证顺序)
docker compose up -d

# 5. 健康检查
sleep 30
for port in 8080 8081 8082 3045; do
    curl -fs -o /dev/null http://localhost:$port/ && echo "✓ $port OK"
done
```

### 19.3.2 数据库迁移

升级 v3.x → v3.y 通常需要跑 SQL 迁移:
```bash
# 看新版本是否有 db_update.sh
ls stack/dataserver/dataserver/dbconfig/
# 跑迁移
docker compose exec -T db bash -c "mysql -uroot -p\"$MARIADB_ROOT_PASSWORD\" zotprimeprod < /var/www/zotero/misc/db_update.sql"
```

### 19.3.3 升级回滚

```bash
# 1. 停服务
docker compose down

# 2. 恢复 .env
cp .env.backup .env

# 3. 用旧镜像重启
sed -i "s/^VER=.*/VER=v3.2.0/" .env
docker compose up -d

# 4. 恢复数据库(如已迁移)
docker compose exec -T db \
    mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" zotprimeprod < backup-pre-upgrade.sql
```

### 19.3.4 客户端升级

服务端升级后,客户端通常自动兼容(向下兼容)。如需强制升级:
- 通知用户重新下载客户端
- 通过 `bin/serve-clients.sh` 更新 HTTP 服务
- Win7 装机:重新跑 PowerShell 注入脚本

## 19.4 灾备恢复

### 19.4.1 恢复场景

| 场景 | 恢复方法 |
|------|----------|
| 单容器崩溃 | `docker compose up -d <service>` |
| 整个 stack 损坏 | 从备份恢复 .env + db + minio |
| 服务器整机故障 | 新机重装 + 恢复 |
| 数据库损坏 | 从 SQL dump 恢复 |
| MinIO 数据丢失 | 从 mc mirror 备份恢复 |

### 19.4.2 新机恢复流程

```bash
# 1. 准备新机 (Ubuntu 22.04)
./bin/prepare-ubuntu-server.sh

# 2. 拉取最新部署包
scp backup-server:/srv/zotprime/zotprime-intranet-v3.2.0.tar.gz .
tar xzf zotprime-intranet-v3.2.0.tar.gz
cd zotprime-intranet-v3.2.0

# 3. 加载镜像
./load-images.sh

# 4. 恢复 .env
cp /backup/env-backup-20260701 .env
chmod 600 .env

# 5. 部署
./bin/deploy-intranet.sh
# → 选 "n" 跳过自动生成 .env,用回备份的 .env

# 6. 恢复数据库
docker compose exec -T db \
    mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" zotprimeprod < /backup/db-20260701.sql

# 7. 恢复 MinIO
docker run --rm --network zotprime_zotprime \
    -v /backup/minio:/backup \
    minio/mc mirror --quiet \
    /backup/zotero-storage http://minio:9000/zotero-storage

# 8. 验证
curl http://localhost:8080/
curl http://localhost:3045/
```

### 19.4.3 RTO / RPO 目标

| 指标 | 目标 | 当前可达 |
|------|------|----------|
| RTO (恢复时间) | < 2 小时 | 1-2 小时(新机重装+恢复) |
| RPO (数据丢失) | < 24 小时 | 日备份 → RPO 24 小时 |

## 19.5 监控告警

### 19.5.1 健康检查端点

当前用 `bin/deploy-intranet.sh` 中的 `health_check()` 做一次性检查。

如需持续监控:
```bash
# 创建 health-watch.sh (循环 curl)
cat > /usr/local/bin/zotprime-health.sh <<'EOF'
#!/bin/bash
URLS=(
    "http://localhost:8080/|Zotero API"
    "http://localhost:8081/|Stream Server"
    "http://localhost:8082/login|Admin"
    "http://localhost:3045/|Portal"
)
for entry in "${URLS[@]}"; do
    IFS='|' read -r url name <<< "$entry"
    code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "$url" 2>/dev/null)
    if [ "$code" != "200" ]; then
        echo "[$(date -Is)] ALERT $name ($url) → $code"
        # 发邮件/钉钉 webhook
    fi
done
EOF
chmod +x /usr/local/bin/zotprime-health.sh

# crontab 每 5 分钟
*/5 * * * * /usr/local/bin/zotprime-health.sh 2>&1 | logger -t zotprime
```

### 19.5.2 钉钉 webhook 告警

```bash
# 在 health-watch.sh 里加
WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=xxx"
curl -X POST "$WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"[ZotPrime] $name DOWN ($code)\"}}"
```

### 19.5.3 资源监控

```bash
# 实时
docker stats

# 内存排序
docker stats --no-stream --format "{{.Name}}: {{.MemUsage}}" | sort -t: -k2 -h -r
```

### 19.5.4 日志关键字告警

```bash
# watch OOMKilled
docker compose logs -f | grep --line-buffered "OOMKilled\|FATAL\|Connection refused" \
    | while read line; do
        # 发告警
        curl -X POST "$WEBHOOK" -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"$line\"}}"
    done
```

## 19.6 故障排查速查表

### 19.6.1 服务起不来

| 症状 | 排查 | 修复 |
|------|------|------|
| db 一直 restart | `docker compose logs db` | 检查 `.env` 的 MariaDB 密码 |
| elasticsearch exit code 78 | 看 max_map_count | `sysctl -w vm.max_map_count=262144` |
| dataserver 启动慢 | `docker logs <id>` | 等 30 秒,composer install 慢 |
| minio "bucket already exists" | 看 init 容器日志 | 通常可忽略,自动跳过 |
| phpmyadmin 502 | 看 nginx upstream | db 未 healthy,等 |

### 19.6.2 网络问题

| 症状 | 排查 | 修复 |
|------|------|------|
| 客户端连不上 | `curl http://<SERVER_IP>:8080/` | 检查 SERVER_IP + UFW |
| 端口 8080 不通 | `ss -ltn \| grep 8080` | UFW allow / 服务未启动 |
| Admin 502 | `docker compose logs zotprime-admin` | API_SUPER_TOKEN_HASH 不匹配 |
| MinIO 9000 公网可达 | `ss -ltn \| grep 9000` + UFW | 危险!禁止对外 |

### 19.6.3 性能问题

| 症状 | 排查 | 修复 |
|------|------|------|
| 同步慢 | `docker stats` 看 ES 内存 | `ES_JAVA_OPTS=-Xms512m -Xmx512m` |
| 上传慢 | 看 minio 磁盘 IO | 用 SSD |
| 客户端卡顿 | 看 Zotero storage 大小 | 清理本地 PDF 缓存 |
| CPU 100% | `docker stats` | 看是哪个容器,kill -9 或扩容 |

### 19.6.4 数据问题

| 症状 | 排查 | 修复 |
|------|------|------|
| "library version mismatch" | 客户端 vs 服务端 | 升级客户端 / 删本地 storage 全量重下 |
| 附件丢失 | 看 MinIO bucket | `mc ls local/zotero-storage` |
| 用户密码忘 | `bin/admin.sh docker user reset-password` | 用 API_SUPER_TOKEN 重置 |

## 19.7 性能基准 (待 PR#6 E2E 实测)

| 指标 | 目标 |
|------|------|
| 1000 条目同步 | < 5 分钟 |
| 并发用户 | 50+ |
| 24h 内存泄漏 | 0 |
| 服务启动到就绪 | < 2 分钟 |

## 19.8 常用命令速查

```bash
# 状态
docker compose ps
docker stats

# 日志
docker compose logs -f <service>
docker compose logs --since="1h" <service>

# 重启
docker compose restart <service>
docker compose up -d

# 进入容器
docker compose exec <service> bash
docker compose exec db mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" zotprimeprod

# 资源清理
docker system df
docker system prune -a   # 警告:会删未用镜像

# 备份
docker compose exec -T db mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" zotprimeprod > backup.sql
```

## 19.9 升级清单

每次版本升级前确认:

- [ ] 数据库已备份
- [ ] .env 已备份
- [ ] 在维护窗口(通知用户)
- [ ] 检查 release notes (GitHub Releases)
- [ ] 新镜像已 build & push (`bin/build-local.sh`)
- [ ] 升级后健康检查 6 端口
- [ ] 验证至少一个用户能 sync
- [ ] 通知用户升级完成

## 19.10 与其他章节的关系

- **前置:** [16-intranet-deployment.md](16-intranet-deployment.md), [17-intranet-package.md](17-intranet-package.md)
- **Win7 客户端:** [18-win7-compatibility.md](18-win7-compatibility.md)
- **用户手册:** [`../user-manual/`](../user-manual/README.md)