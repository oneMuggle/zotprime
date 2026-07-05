# 30. 客户端分发指南 (面向部门 IT)

> 部门 IT 协调员/系统管理员:把客户端安装包分发给最终用户。三种分发通道:HTTP、SMB、U 盘。

## 30.1 前置

服务端已经按 [15-ubuntu-server-setup.md](../technical/15-ubuntu-server-setup.md) + [16-intranet-deployment.md](../technical/16-intranet-deployment.md) 部署完成,并已经运行 `bin/package-for-intranet.sh` 生成 `intranet-package/clients/`。

## 30.2 通道 A: HTTP 文件服务器 (推荐)

### 一键启动

```bash
./bin/serve-clients.sh
```

输出:
```
==========================================
  ✅ 客户端 HTTP 文件服务器已启动
==========================================

  访问地址:
    http://192.168.1.100:8000/

  各客户端下载:
    Win10+ (8.0.1):   http://192.168.1.100:8000/win10plus/
    Win7  (5.0.96.3): http://192.168.1.100:8000/win7/

  停止服务: ./bin/serve-clients.sh --stop
```

### 高级选项

```bash
# 自定义端口
PORT=9000 ./bin/serve-clients.sh

# 自定义文档根 (例如换成另一个版本的 intranet-package)
DOC_ROOT=/srv/zotprime/clients/v3.2.0 ./bin/serve-clients.sh

# 集成到 deploy-intranet.sh (PR#4 改造)
# 部署完自动启动 HTTP 服务器,打印 URL
```

### 用户使用

把 URL 发给部门用户(邮件/微信/钉钉):
```
请安装 Zotero 客户端:
Win10/11: http://192.168.1.100:8000/win10plus/
Win7/8.1: http://192.168.1.100:8000/win7/  (需 IT 协助)
```

### 防火墙

UFW 已开放 8000 端口(由 [15-ubuntu-server-setup.md](../technical/15-ubuntu-server-setup.md) 配置)。如改用其他端口,记得:
```bash
sudo ufw allow <新端口>/tcp comment 'Client HTTP Server'
```

## 30.3 通道 B: SMB 共享

适合多部门共享,但需要预先有 samba 服务。

### 服务端:配置 samba

```bash
sudo apt install -y samba

# 创建共享目录
sudo mkdir -p /srv/samba/zotprime/clients
sudo chown -R nobody:nogroup /srv/samba/zotprime

# 首次同步客户端
./bin/sync-clients-to-smb.sh /srv/samba/zotprime/clients
```

编辑 `/etc/samba/smb.conf`:
```ini
[zotprime]
path = /srv/samba/zotprime
browseable = yes
read only = yes
guest ok = no
valid users = @zotprime-users
comment = ZotPrime client installers
```

```bash
# 创建 zotprime-users 组
sudo groupadd zotprime-users
sudo usermod -aG zotprime-users <用户名>
sudo smbpasswd -a <用户名>
sudo systemctl restart smbd
```

### 客户端分发到其他机器

```bash
# 把客户端同步到另一台 SMB 服务器 (例如 fileserver)
./bin/sync-clients-to-smb.sh //fileserver/zotprime/clients
```

> **注意:** 目标需先 mount 到本地路径(用 `cifs-utils` 包)。

### 用户使用

Windows 资源管理器地址栏输入:
```
\\<samba-server-ip>\zotprime\clients\win10plus\
```

或映射网络驱动器:
```
\\<samba-server-ip>\zotprime\clients  →  Z: 盘
```

## 30.4 通道 C: U 盘 (离线/出差)

适合内网不通的部门、出差到外地的同事。

### 构建 U 盘包

```bash
DATASERVER_URL="http://192.168.1.100:8080/" \
STREAM_URL="ws://192.168.1.100:8081/" \
./bin/build-usb-package.sh /tmp/ZotPrime-Setup-USB
```

输出目录结构:
```
ZotPrime-Setup-USB/
├── README.txt
├── win10plus/
│   └── Zotero-8.0.1_win-x86_64-setup.exe
├── win7/
│   ├── Zotero-5.0.96.3_win-x86_64-setup.exe
│   ├── VC_redist.x64.exe   (需手动下载)
│   └── set-zotero-dataserver.ps1
└── SHA256SUMS
```

### 准备 U 盘

1. 格式化 U 盘 (FAT32/NTFS,至少 8GB)
2. 把整个 `ZotPrime-Setup-USB/` 目录内容拷贝到 U 盘根目录
3. **下载 VC++ 2013 Redist** (`VC_redist.x64.exe`) 放入 `win7/` 子目录:
   - 链接: https://aka.ms/vs/17/release/vc_redist.x64.exe
   - 替代源: https://www.microsoft.com/en-us/download/details.aspx?id=40784

### 分发

把 U 盘交给用户,告知:
- Win10/11: 看 `README.txt` 的 "Windows 10 / 11 用户" 章节,直接双击安装
- Win7/8.1: 看 `README.txt` 的 "Windows 7 SP1 / 8.1 用户" 章节,**必须由 IT 协助跑一次 PowerShell**

## 30.5 跟踪装机 (可选)

`bin/track-client-install.sh` (计划中) 会记录装机情况到 CSV,管理员用 `bin/admin.sh docker report installs` 查看。当前可跳过。

## 30.6 故障排查

### HTTP 服务器起不来?

```bash
# 看 docker 错误
docker logs zotprime-client-www

# 端口冲突
sudo ss -ltnp | grep :8000

# 文档根目录权限
ls -la intranet-package/clients/
```

### SMB 用户访问被拒?

```bash
# 检查 samba 用户密码
sudo smbpasswd <用户名>

# 检查 valid users 配置
sudo testparm -s
```

### U 盘在 Win7 上读不出来?

- 重新格式化为 NTFS (FAT32 不支持 >4GB 单文件,虽然 Win7 客户端不到这个大小)
- 用 `lsblk` 看 U 盘是否被正确识别 (Linux)

## 30.7 相关脚本

| 脚本 | 用途 |
|------|------|
| `bin/serve-clients.sh` | 启动 HTTP 文件服务器 |
| `bin/sync-clients-to-smb.sh` | 同步到 SMB 共享 |
| `bin/build-usb-package.sh` | 构建 U 盘分发包 |
| `bin/package-for-intranet.sh` | 生成 `intranet-package/clients/` 源 |
| `bin/deploy-intranet.sh` | 一键部署 + 集成 HTTP 启动 (PR#4) |

## 30.8 下一步阅读

- [00-quickstart.md](00-quickstart.md) - 用户快速上手
- [10-win7-installation.md](10-win7-installation.md) - Win7 装机 runbook
- [20-administrator-guide.md](20-administrator-guide.md) - 管理员速查