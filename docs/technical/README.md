# ZotPrime 技术手册

面向系统管理员与开发者的部署、运维、架构文档。

## 章节目录

| # | 章节 | 内容 |
|---|------|------|
| 15 | [Ubuntu 22.04 环境准备](15-ubuntu-server-setup.md) | 服务器初始化、Docker 安装、防火墙、时区、内核参数 |
| 16 | [内网部署 (13 服务 Docker Compose)](16-intranet-deployment.md) | 服务架构、镜像清单、部署方式、健康检查、客户端 IP 注入 |
| 17 | [内网离线包打包](17-intranet-package.md) | docker save 导出、tar.gz 打包、load-images.sh 使用 |
| 18 | [Win7 兼容性](18-win7-compatibility.md) | 5.0.96.3 客户端 + C 路径 PowerShell 注入 |
| 19 | [运维手册](19-operations-manual.md) | 日志、备份、升级、灾备、监控、故障排查 |

## 文档约定

- **按场景阅读:** 内网部署从 15 → 16 → 17 顺序读;客户端使用看 18;日常运维看 19
- **文件命名:** `XX-topic-name.md` (XX 为两位章节号)
- **过时文档:** 按项目规范"过时文档立即删除",不保留历史版本

## 相关文档

- **计划文档:** `docs/plans/` (仅保留进行中的计划,完成后删除)
- **用户手册:** [`docs/user-manual/`](../user-manual/README.md)
- **代码根目录:** [`../`](../) - 项目 README,部署脚本,源码

## 快速链接

| 任务 | 章节 |
|------|------|
| 新装一台 Ubuntu 服务器 | [15](15-ubuntu-server-setup.md) |
| 部署 13 个 Docker 服务 | [16](16-intranet-deployment.md) |
| 打包离线部署包 | [17](17-intranet-package.md) |
| 装 Win7 客户端 | [18](18-win7-compatibility.md) |
| 出问题排查 | [19](19-operations-manual.md) |