# 9. Windows 7 安装说明

## 9.1 我是 Win7 用户，我该装哪个版本？

如果你的电脑运行的是 **Windows 7 SP1 64 位**（右键"我的电脑"→"属性"可查看系统类型），请按本章步骤安装 **Zotero 5.0.96.3 for Win7** 版本。

> 警告：Zotero 8.0 不支持 Windows 7，请勿下载。

## 9.2 系统要求

| 项 | 最低要求 |
|----|----------|
| 操作系统 | Windows 7 SP1 (64 位) |
| VC++ 运行库 | 2013 Redist x64 或更新 |
| 硬盘空间 | 500 MB |
| 内存 | 2 GB |

## 9.3 安装步骤

### 步骤 1：下载安装包

从内网部署平台下载 `Zotero-5.0.96.3_win-x86_64-setup.exe`（约 50 MB）。

### 步骤 2：安装 VC++ 2013 Redist（如已安装可跳过）

[下载链接](https://www.microsoft.com/en-us/download/details.aspx?id=40784)，双击默认安装。

### 步骤 3：双击安装包

按提示点击"下一步"，默认安装到 `C:\Program Files\Zotero`。

### 步骤 4：首次启动

启动 Zotero，会自动弹出"新建账号"或"登录已有账号"窗口。

## 9.4 配置内网 dataserver

**重要**：Zotero 5.0.96.3 安装包在构建时已注入内网 dataserver 地址，**首次启动时不需要手动配置**。

如启动后同步时报 "Cannot connect to api.zotero.org"，说明注入未生效（罕见），请联系运维执行 `set-zotero-dataserver.ps1` 兜底脚本。

## 9.5 验证安装

1. Zotero 启动后，菜单 `编辑 → 设置 → 同步` 应显示"连接到内网 ZotPrime"
2. 顶部状态栏的同步图标点击后应能正常同步
3. 添加一条文献，等待几秒后能看到云端图标

## 9.6 常见问题

### Q1: 启动时弹窗"无法启动此应用程序，因为计算机中缺少 MSVCR120.dll"

A: VC++ 2013 Redist 没装好，重新装一次（见 9.3 步骤 2）。

### Q2: 同步时报 "SSL certificate problem"

A: 浏览器访问 `http://<SERVER_IP>:8080/`，把证书导出后双击装到"受信任的根证书颁发机构"。

### Q3: 同步时报 "Cannot connect to api.zotero.org"

A: 注入未生效。联系运维推送 `set-zotero-dataserver.ps1` 兜底脚本。

## 9.7 相关链接

- 内网 dataserver 入口：`http://<SERVER_IP>:8080/`
- 技术文档：`docs/technical/18-win7-compatibility.md`
