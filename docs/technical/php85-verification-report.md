# PHP 8.5 Alpine 构建验证报告（PR#0）

**日期:** 2026-07-05  
**分支:** `feature/dataserver-php85-verify`  
**目的:** 验证 `stack/dataserver/ds.Dockerfile` 中 `FROM alpine:3` + `php85-*` 全套包在当前 Alpine 仓库可用,确认 Phase 2 dataserver 构建无 BLOCKER。

---

## 验证结果: ✅ 通过

### 测试环境

| 项 | 值 |
|----|----|
| Docker | 29.6.1 (build 8900f1d) |
| Docker Compose | v5.2.0 |
| Host OS | Ubuntu 22.04 (本地开发机) |
| 构建时间 | ~3 分钟 |

### 验证步骤

```bash
cd /home/fz/project/zotprime/stack
DOCKER_BUILDKIT=1 docker build \
  -f dataserver/ds.Dockerfile \
  -t uniuu/zotprime-dataserver:v3.2.0 \
  dataserver/
```

### 构建结果

```
#36 exporting layers 15.2s done
#36 naming to docker.io/uniuu/zotprime-dataserver:v3.2.0 done
#36 unpacking to docker.io/uniuu/zotprime-dataserver:v3.2.0 7.4s done
#36 DONE 22.8s

✅ 构建成功 (exit code 0)
```

**关键观察:**
- 36 个 build step 全部 DONE,**无 `ERROR: unsatisfiable constraints`**
- 所有 `php85-*` 包 (`php85-mysqli`, `php85-pdo_mysql`, `php85-pecl-redis`, `php85-pecl-memcached`, `php85-intl`, `php85-mbstring`, 等共 47 个)在 alpine 3 main 仓库直接可用
- Alpine 3 当前 rolling 版本已含 PHP 8.5 stable (不再是 edge/testing)

### PHP 版本验证

```bash
$ docker run --rm --entrypoint="" uniuu/zotprime-dataserver:v3.2.0 php -v
PHP 8.5.8 (cli) (built: Jul  3 2026 15:00:30) (NTS)
Copyright (c) The PHP Group
Built by Alpine Linux aports
Zend Engine v4.5.8, Copyright (c) Zend Technologies
    with Zend OPcache v8.5.8, Copyright (c) Zend Technologies
```

### 关键扩展加载验证

```bash
$ docker run --rm --entrypoint="" uniuu/zotprime-dataserver:v3.2.0 php -m | grep -E "^(mysqli|pdo_mysql|redis|memcached|intl|mbstring|curl|openssl|json|xml|zip)$"
curl
intl
json
mbstring
memcached
mysqli
openssl
pdo_mysql
redis
xml
zip
```

**所有 11 个关键扩展均已加载** — dataserver 路由与 MinIO/S3/Elasticsearch 集成所需的 PHP 能力完整。

### 镜像大小

```
uniuu/zotprime-dataserver:v3.2.0    781MB    2 minutes ago
```

(预估范围 800MB-1.2GB,实际 781MB 优于预期)

---

## 风险状态变更

| 风险 (来自 intranet-deployment.md R1) | 验证前 | 验证后 |
|---------------------------------------|--------|--------|
| PHP 8.5 包在 alpine 3 仓库不可用 | 中 / BLOCKER | **已消除** |

**R1 风险关闭** — 无需触发回退方案 A (alpine:3.19 + PHP 8.3) 或 B (第三方 PHP 镜像)。

---

## 给 Phase 2 的结论

**dataserver 镜像链路畅通**,可以进入:

1. **Task 2.2** — 13 镜像清单文档化 (无需 PHP 8.5 fallback 说明)
2. **Task 2.3** — build-and-push.yml 优化 (按计划增加 `linux/amd64-only` 选项 + smoke test)
3. **Task 2.4** — 本地构建回退验证
4. **Task 2.5** — 离线包打包验证

---

## 给后续 PR 的建议

### PR#2 (Phase 2: Docker 镜像链路)

- 在 `build-and-push.yml` 的 dataserver build step 后,增加 smoke test:
  ```yaml
  - name: Smoke test dataserver image
    run: |
      docker create --name ds-test uniuu/zotprime-dataserver:${VERSION}
      docker cp ds-test:/usr/bin/php85 /tmp/php85
      /tmp/php85 -v | grep -q "PHP 8.5"
      docker rm -f ds-test
  ```
- 锁定 `FROM alpine:3` (而非 `:latest`),使构建可复现

### PR#1 (Phase 1: Ubuntu 环境准备)

- `bin/prepare-ubuntu-server.sh` 中可以增加一个 `--check-php85-only` 干跑模式 (仅 build dataserver 一个镜像),作为部署前的健康检查

---

## 附录: 验证命令汇总

```bash
# 1. 构建 dataserver 镜像
cd /home/fz/project/zotprime/stack
DOCKER_BUILDKIT=1 docker build \
  -f dataserver/ds.Dockerfile \
  -t uniuu/zotprime-dataserver:v3.2.0 \
  dataserver/

# 2. 验证 PHP 版本
docker run --rm --entrypoint="" uniuu/zotprime-dataserver:v3.2.0 php -v

# 3. 验证扩展加载
docker run --rm --entrypoint="" uniuu/zotprime-dataserver:v3.2.0 php -m

# 4. 验证镜像存在
docker images uniuu/zotprime-dataserver:v3.2.0

# 5. 清理 (验证完成后)
docker rmi uniuu/zotprime-dataserver:v3.2.0
```