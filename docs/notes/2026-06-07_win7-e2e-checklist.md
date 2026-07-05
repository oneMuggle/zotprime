# Win7 SP1 E2E 验证记录（待补）

> **状态：** 未执行。本机无 Vagrant / Win7 VM。需要在有 Win7 SP1 x64 镜像的环境下补跑。
> **关联 PR：** #5
> **关联 spec：** docs/superpowers/specs/2026-06-07-win7-compatibility-design.md §7.5

## 验证环境准备

- Vagrant box 来源（待定）：`win7-sp1-eval`
- Vagrantfile 模板见 PR#5 Task 5.5 描述
- 镜像需包含 Win7 SP1 x64 + PowerShell 5.1 + .NET Framework 4.5+

## 验证清单（7 步）

- [ ] 1. 干净环境安装 5.0.96.3 安装包成功
- [ ] 2. 首次启动不报"缺少 dll"
- [ ] 3. 配同步连到 ZotPrime dataserver，上传一条文献
- [ ] 4. 在 Win10 客户端登录同一账号，能看到该条文献
- [ ] 5. 反向：Win10 添加一条，Win7 同步下来
- [ ] 6. Word 集成（zotero-win32-transfw）正常
- [ ] 7. 卸载干净，无残留注册表

## 失败模式

如某步失败，记录：
- 错误信息（截图/日志）
- 复现步骤
- 关联代码/配置改动建议
- 是否升级 issue 跟踪
