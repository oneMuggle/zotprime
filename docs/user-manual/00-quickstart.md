# 00. 5 分钟快速上手

> 适用于 Win10/11 用户。Win7 用户请看 [10-win7-installation.md](10-win7-installation.md)。

## 00.1 获取客户端

从 IT 处获取 Zotero 安装包,有三种渠道:

| 渠道 | 适合场景 | 步骤 |
|------|----------|------|
| **HTTP 下载** | 单台机器快速装 | 浏览器打开 IT 提供的 URL → 下载 win10plus/Zotero-8.0.1_win-x86_64-setup.exe |
| **SMB 共享** | 部门多台机器 | 资源管理器输入 `\\fileserver\zotprime\clients\win10plus\` |
| **U 盘** | 离线/出差 | 从 IT 拷贝整个 U 盘,本地打开 `win10plus/` 文件夹 |

## 00.2 安装

1. 双击下载的 `Zotero-8.0.1_win-x86_64-setup.exe`
2. 同意许可 → "下一步" (可全默认)
3. 等待安装完成 (约 1-2 分钟)
4. 桌面会出现 Zotero 图标

## 00.3 启动并登录

1. 双击桌面 Zotero 图标
2. **首次启动较慢 (1-2 分钟)**,不要关闭
3. 菜单: **Edit → Preferences → Sync**
4. 输入 IT 给你的用户名 + 密码 → 点 "Set Up Syncing"
5. 等待首次同步完成 (取决于库大小,可能 5-30 分钟)

## 00.4 验证

Preferences → Sync 页面应该显示:
- **Username:** 你的用户名
- **Last sync time:** 刚刚的时间

如果显示空白或报错,联系 IT。

## 00.5 添加文献

- **拖拽 PDF 到 Zotero 主窗口** → 自动识别元数据
- **浏览器扩展 (Connector):** Chrome/Firefox 装 Zotero Connector,访问期刊网站时点图标
- **手动创建:** 点工具栏绿色 "+" → 选文献类型 → 填写字段

## 00.6 常见问题

**Q: Sync 按钮是灰色的?**
A: 服务器没连上。检查:
- 公司内网 VPN 是否连接
- 是否能 ping 通 IT 给的服务器 IP

**Q: 报 "Cannot connect to server"?**
A: 联系 IT 检查服务端是否运行 (`http://<SERVER_IP>:8080/` 应能打开)。

**Q: 文献 PDF 全文下载不了?**
A: 这是正常行为 — 客户端不直接下载全文 PDF,需通过 Sync 同步元数据,然后用 Zotero Connector 或手动拖拽补充。

## 00.7 进阶使用

- **Word 插件:** Zotero 安装时自动装,Word 工具栏会有 Zotero 选项卡
- **引用样式:** Preferences → Cite → 选 GB/T 7714 或其他
- **笔记:** 选中条目 → 右键 → Add Note

## 00.8 下一步阅读

- [10-win7-installation.md](10-win7-installation.md) - Win7/8.1 用户
- [30-distribution.md](30-distribution.md) - 部门 IT 协调员
- [20-administrator-guide.md](20-administrator-guide.md) - 系统管理员速查