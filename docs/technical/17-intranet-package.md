# 17. 内网离线包打包

> 面向系统管理员。在**能上网的机器**上,把 13 个 Docker 镜像 + 双版本客户端 + 部署脚本打成 tar.gz,传输到**内网/离线**的 Ubuntu 服务器部署。

---

## 17.1 为什么需要离线包?

内网/离线环境通常无法访问 Docker Hub,也无法从 `download.zotero.org` 下载客户端。两阶段部署解决:

```
[联网构建机]                                     [内网服务器]
   │
   ├─ docker build (13 镜像)
   ├─ docker save (→ 13 个 .tar)
   ├─ docker build (Win10+/Win7 客户端)
   ├─ tar czf → zotprime-intranet-VER.tar.gz
   │
   ▼
   U 盘 / 内网文件服务器传输
   │
   ▼
   ./load-images.sh (docker load)
   ./bin/deploy-intranet.sh (一键启动)
```

## 17.2 打包命令

```bash
cd /home/fz/project/zotprime
./bin/package-for-intranet.sh
```

默认使用 `IMAGE_TAG=v3.2.0`,可覆盖:
```bash
IMAGE_TAG=v3.3.0 ./bin/package-for-intranet.sh
```

输出:`build/zotprime-intranet-v3.2.0.tar.gz` (~9-10 GB)

## 17.3 打包步骤详解

### 17.3.1 前置检查

```bash
# Docker
docker --version          # ≥ 20.10
docker compose version    # ≥ 2.20

# 子模块 (5 个)
git submodule status
# 期望全部 + (已初始化)
```

### 17.3.2 构建 13 个服务端镜像

由 `bin/build-local.sh` 完成。详见 [16-intranet-deployment.md §16.6](16-intranet-deployment.md)。

### 17.3.3 构建客户端

由 `bin/build-local.sh [14/14] client` 完成。详见 [16-intranet-deployment.md §16.11](16-intranet-deployment.md)。

### 17.3.4 导出 Docker 镜像

`bin/package-for-intranet.sh` 用 `docker save` 把 13 个镜像导出为 tar:

```bash
services=(
    "dataserver:uniuu/zotprime-dataserver"
    "db:uniuu/zotprime-db"
    ...
)
for entry in "${services[@]}"; do
    docker save "$tag" -o "$PACKAGE_DIR/images/${short_name}.tar"
done
```

### 17.3.5 打包客户端安装包

把 dist/win10plus/ 和 dist/win7/ 复制到 intranet-package/clients/,生成 SHA256SUMS:

```
intranet-package/clients/
├── win10plus/
│   ├── Zotero-8.0.1_win-x86_64-setup.exe
│   └── SHA256SUMS
└── win7/
    ├── Zotero-5.0.96.3_win-x86_64-setup.exe
    └── SHA256SUMS
```

### 17.3.6 生成 clients-manifest.json

```json
{
  "version": "${VER}",          // 与 IMAGE_TAG 一致 (PR#4 bug fix)
  "clients": {
    "win10plus": { "installer": "...", "sha256": "...", "min_os": "10.0", "arch": ["x86_64"] },
    "win7":      { "installer": "...", "sha256": "...", "min_os": "6.1",  "arch": ["x86_64"] }
  }
}
```

### 17.3.7 复制项目文件 + 创建 load-images.sh

`rsync` 复制整个项目到 `$PACKAGE_DIR/`(排除 `.git`/`build`/`node_modules`/`vendor` 等)。

生成 `load-images.sh`:
```bash
#!/bin/bash
# 在内网服务器上跑,导入所有镜像
for img in images/*.tar; do
    docker load -i "$img"
done
```

### 17.3.8 压缩为 tar.gz

```bash
cd build
tar czf zotprime-intranet-v3.2.0.tar.gz zotprime-intranet-v3.2.0/
```

## 17.4 包结构

```
zotprime-intranet-v3.2.0/
├── load-images.sh                   # 一键导入 13 镜像
├── 内网部署说明.md                  # 中文 runbook (简化版)
├── docker-compose.yml              # 同源码
├── .env_example                    # 配置模板
├── bin/                            # 部署脚本
│   ├── deploy-intranet.sh
│   ├── package-for-intranet.sh
│   ├── serve-clients.sh
│   ├── build-usb-package.sh
│   ├── admin.sh
│   ├── prepare-ubuntu-server.sh
│   └── set-zotero-dataserver.ps1
├── stack/                          # 13 服务源码 (Dockerfile 等)
│   ├── dataserver/
│   ├── db/
│   └── ...
├── images/                         # 13 个 docker save 产物
│   ├── dataserver.tar
│   ├── db.tar
│   └── ...
└── intranet-package/clients/       # 客户端
    ├── win10plus/
    └── win7/
```

## 17.5 内网部署流程

```bash
# 1. 在内网服务器上解压
tar xzf zotprime-intranet-v3.2.0.tar.gz
cd zotprime-intranet-v3.2.0

# 2. 导入 13 镜像
./load-images.sh
# 13 个镜像导入完成,约需 1-3 分钟

# 3. 一键部署
chmod +x bin/deploy-intranet.sh
./bin/deploy-intranet.sh
```

部署脚本会自动:
1. 检测 Docker / 内核参数
2. 生成 .env (随机密钥)
3. 启动 13 服务
4. 健康检查 6 端口
5. 启动 HTTP 文件服务器 (PR#4)
6. 打印登录凭据 + 客户端 URL

## 17.6 镜像大小估算 (实测 2026-07-05)

| 镜像 | 大小 |
|------|------|
| localstack | 2.62GB |
| elasticsearch | 2.15GB |
| phpmyadmin | 1.09GB |
| admin | 808MB |
| dataserver | 781MB |
| db | 472MB |
| streamserver | 346MB |
| portal | 327MB |
| tinymceclean | 271MB |
| minio | 241MB |
| miniomc | 117MB |
| redis | 57MB |
| memcached | 20MB |
| **13 镜像总计** | **~9.9GB** |
| + 客户端 + 脚本 | ~10.2GB |
| **tar.gz 压缩后** | **~9-10GB** |

## 17.7 传输方式

### 17.7.1 U 盘

- **容量:** 16GB+ U 盘
- **文件系统:** exFAT 或 NTFS (ext4 在 Windows 上读不了)
- **拷贝时间:** USB 3.0 约 5-10 分钟

### 17.7.2 内网文件服务器

```bash
# 拷贝到内网文件服务器
scp build/zotprime-intranet-v3.2.0.tar.gz admin@fileserver:/srv/zotprime/
# 或 rsync
rsync -av --progress build/zotprime-intranet-v3.2.0.tar.gz fileserver:/srv/zotprime/
```

### 17.7.3 内网 HTTP / NFS

`bin/serve-clients.sh` serve 的是 `intranet-package/clients/`,**不**包含服务端镜像 (镜像太大)。如需 serve 完整包:

```bash
cd build
python3 -m http.server 8080
# 内网用户访问: http://<server>:8080/zotprime-intranet-v3.2.0.tar.gz
```

## 17.8 故障排查

### Q1: 打包时某镜像构建失败?

检查 `bin/build-local.sh` 输出。常见原因:
- 子模块未初始化:`git submodule update --init --recursive`
- 网络问题:alpine apt / PECL / npm 偶发 503

### Q2: tar.gz 太大,U 盘装不下?

- 排除某些镜像(测试环境可不要 phpmyadmin / localstack)
- 用更高压缩率:`tar cJf ...xz`(但慢 3-5 倍)
- 分卷:`split -b 4G zotprime-intranet-v3.2.0.tar.gz zp-part-`

### Q3: 内网服务器导入镜像失败?

- `load-images.sh` 输出会指明哪个 tar 失败
- 检查 tar 完整性:`sha256sum -c images/*.sha256`
- 检查磁盘空间:`df -h /var/lib/docker`(需 ~12GB)

### Q4: docker compose up 报 "image not found"?

镜像 tag 不匹配。检查 `.env` 的 `VER` 与 `docker images | grep uniuu/zotprime` 是否一致。

## 17.9 与其他章节的关系

- **前置:** [16-intranet-deployment.md](16-intranet-deployment.md) (镜像清单 + 健康检查)
- **后续:** [19-operations-manual.md](19-operations-manual.md) (备份/升级流程)