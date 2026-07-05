# 18. Win7 兼容性

> 本章描述 zotprime 在新分支 `feature/win7-compatibility` 下对 Windows 7 SP1 x64 客户端的兼容方案。

## 18.1 兼容性矩阵

| Windows 版本 | dataserver 协议 | Zotero 客户端 | 状态 |
|--------------|-----------------|---------------|------|
| Win 11 (10.0 build ≥ 22000) | 8.0+ | 8.0.1 | 支持 |
| Win 10 (10.0 build < 22000) | 8.0+ | 8.0.1 | 支持 |
| Win 8.1 (6.3) | 8.0+ | **5.0.96.3** | 支持 |
| **Win 7 SP1 x64 (6.1)** | 8.0+ | **5.0.96.3** | 支持（实验性） |
| Win Vista (6.0) | - | - | 不支持 |
| Win XP (5.1/5.2) | - | - | 不支持 |

## 18.2 构建命令

### 现代版（8.0.1，Win10+ 默认）

```bash
bin/build-local.sh
# 产物: dist/Zotero-8.0.1_win-x86_64-setup.exe
```

### Win7 版（5.0.96.3，Win7/8.1）

```bash
WIN7=1 bin/build-local.sh
# 产物: dist/Zotero-5.0.96.3_win-x86_64-setup.exe
# 内含 A' 注入：dataserver URL 已写入 XPI 的 resource/config.js
```

### 内网部署包

```bash
bin/package-for-intranet.sh
# 产物: intranet-package/
#   ├── clients/win10plus/  (现代版 .exe + .sha256)
#   ├── clients/win7/       (5.0.96.3 .exe + .sha256)
#   └── clients-manifest.json
```

### dataserver URL 兜底（A' 失败时用）

```powershell
# 在 Win7 客户端上以管理员权限打开 PowerShell 5.1+
.\bin\set-zotero-dataserver.ps1 \
    -DataServerUrl "http://zotprime.local:8080/" \
    -StreamServerUrl "ws://zotprime.local:8081/"
```

## 18.3 dataserver URL 注入原理（A' 路径）

1. 拉官方 `Zotero-5.0.96.3_win-x86_64-setup.exe`
2. 7z 解 NSIS 自解压包
3. 定位 Zotero 扩展 `zotero@chnm.org.xpi`
4. 解 XPI（zip 格式）→ 改 `resource/config.js`：
   - `https://api.zotero.org` → `${HOST_DS}`
   - `wss://stream.zotero.org` → `${HOST_ST}`
5. 重打包 XPI
6. `makensis` 重编译 NSIS 安装包

与 8.0+ 的 `prebuild_client.Dockerfile` omni.ja 重打包路径完全对称。

## 18.4 限制声明

- **仅 Win7 SP1 x64**：32 位、内核版本 < 6.1 不支持
- **5.0.96.3 协议冻结**：dataserver 升级到 Zotero 6 协议特性时，5.0 客户端可能无法同步新字段
- **Gecko 60 ESR Win7 安全补丁已停止**：仅建议内网隔离环境使用
- **VC++ 2013 Redist 必装**：Win7 干净环境需先安装 [vcredist_x64.exe](https://www.microsoft.com/en-us/download/details.aspx?id=40784)

## 18.5 端到端测试（Win7 SP1 Vagrant VM）

```bash
# 准备 Win7 SP1 镜像
vagrant init win7-sp1
vagrant up

# 验证清单
- [ ] 干净环境安装 5.0.96.3 安装包成功
- [ ] 首次启动不报"缺少 dll"
- [ ] 配同步连到 ZotPrime dataserver，上传一条文献
- [ ] 在 Win10 客户端登录同一账号，能看到该条文献
- [ ] 反向：Win10 添加一条，Win7 同步下来
- [ ] Word 集成（zotero-win32-transfw）正常
- [ ] 卸载干净，无残留注册表
```

## 18.6 相关文件

- 规范：`docs/superpowers/specs/2026-06-07-win7-compatibility-design.md`
- 用户手册：`docs/user-manual/10-win7-installation.md`
- 实施计划：`docs/plans/2026-06-07-win7-compatibility.md`
- 子模块：
  - `client/zotero-standalone-build-win7` @ `5.0.96.3`
  - `client/zotero-client-win7` @ `5.0.96.3`
- 脚本：
  - `bin/detect-win-version.sh`
  - `bin/set-zotero-dataserver.ps1`
  - `bin/build-local.sh`（增 `WIN7=1` 开关）
