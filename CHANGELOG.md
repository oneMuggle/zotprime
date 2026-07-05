# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [v0.4.0] - 2026-07-05

### Added
- test(portal): 引入 Playwright E2E 框架 (`stack/webui/portal/tests/e2e/portal.spec.ts` 11 步覆盖 happy path + auto-migrate + 错误路径)
- test(portal): 11 步 e2e test config (`playwright.config.ts` + `package.json` scripts `e2e` / `e2e:install`)
- ci(e2e): push-all-images.yml `e2e-portal` job 集成 Playwright
- feat(dataserver): 新增 `POST /api/auth/login` 端点(plain password → `password_verify` + MD5 auto-migrate → `{success, userID, apiKey}`)
- feat(portal): login 改用新端点,删除 `crypto.createHash('md5')` + `users.find()` 全表扫描 + `getUserKeys` 二次调用
- docs(notes): F-1 + F-2 + F-3 + F-4 + F-5 + F-6 完成归档
- docs(superpowers): 写两份 spec/plan 文档(portal no-2FA + dataserver bcrypt)

### Changed
- security(dataserver): `createUser` 从 `MD5(?)` 改为 `password_hash(?, PASSWORD_BCRYPT)`
- security(dataserver): `listUsers` 移除 `password` 字段返回(防 hash 暴露给 super-user)
- security(dataserver): `users.password` 从 `char(40)` 扩到 `varchar(60)` 兼容 MD5(32) 与 bcrypt(60)
- chore(portal): 删除 `types/zotero-api-client.d.ts` dead-code
- chore(portal): 清理未引用 deps `bcrypt` / `@types/bcrypt` / `@types/nodemailer`
- ci(e2e): 加上 `API_SUPER_TOKEN` + `MARIADB_ROOT_PASSWORD` secrets 给 e2e step 8 (auto-migrate 测需要)

### Fixed
- pre-existing dataserver bug: `GET /admin/users` 不返回 password 字段导致 login 永远 401(已在 v0.3.0 PR#9 修)
- pre-existing: portal 端 `crypto.createHash('md5')` 客户端 hash,改为服务端 bcrypt 校验
- pre-existing: portal login 全表扫描 `users.find()` 改为专用 `/api/auth/login` 端点
- pre-existing: 14 个 lint 错误(`any`→`unknown`, `require()`→`import`, import 顺序)

### Known Limitations
- dataserver `db_update.sh` **不自动跑** (entrypoint.sh 不调用)。新部署需要在 entrypoint 或 init 步骤显式跑 `db_update.sh`,或手动 `docker exec ... ALTER TABLE users MODIFY password varchar(60)`
- portal `session.email` 在 F-1+F-3 改造后为空字符串(auth endpoint 不返回 email)
- e2e step 7 (rate limiting) 仍未实际强制,config.yaml 配置 `auth_requests_per_minute: 5` 未被代码读取
- e2e step 8 (auto-migrate 测) 用 `docker exec mariadb` 直接改 DB,本地 dev OK,CI runner 需要 docker socket 访问

## [v0.3.0] - 2026-07-05

### Added
- feat(portal): 内网部署支持 + 移除二维码 TOTP 二因素验证 (PR#9)
  - 登录/注册成功后直接进入 `/portal`，不再走 `/verify` 二维码设置流程
  - 删除 TOTP 数据层：`stack/webui/portal/lib/totp.ts`、`lib/db.ts`、`app/verify/*` 整体清除
  - 删除 `stack/webui/portal/app/api/auth/verify/route.ts`、`data/.gitkeep`
  - `package.json` 移除 `otpauth`、`qrcode`、`lowdb`、`@types/qrcode`
  - `SessionData` 收缩，移除 `totpSecret` / `totpVerified` 字段
  - `iron-session` 8.x 默认宽容忽略 cookie 中未声明字段，旧会话兼容无额外迁移代码
  - 顺手修复 14 个 pre-existing lint 错误（`any` → `unknown`、`require()` → `import`、修 import 顺序）
  - 新增用户手册章节 `docs/user-manual/50-portal-intranet.md`
- docs(user-manual): add 40-client-features.md — end-user功能全景与内网部署特殊说明

### Fixed
- fix(dataserver): include password column in /admin/users response (PR#9)
  - pre-existing bug：`GET /admin/users` 的 `AdminController::listUsers()` SQL 从不返回 `password` 字段
  - 影响：portal login 流程永远 401（在 TOTP 移除之前就是坏的，端到端不可用）
  - 修复：在 SELECT 中加入 `u.password`，并在 JSON mapper 同步返回字段
  - 端到端验证：fresh user register → login 200；错密码 401
- fix(deploy): bin/deploy-intranet.sh APP_KEY 生成格式错误
  - 旧: `openssl rand -hex 32` 产生 64 字符 hex 字符串 → Laravel Encrypter 报 "Unsupported cipher or incorrect key length"
  - 新: `php -r "echo 'base64:'.base64_encode(random_bytes(32));"` 生成 Laravel 兼容的 base64 前缀 32 字节密钥
  - 影响: admin 面板 HTTP 500 / webadmin 无法登录

## [v0.2.0] - 2026-07-05

### Added
- feat(distribution): client distribution via HTTP/SMB/USB (PR#4) — `bin/serve-clients.sh`、`bin/sync-clients-to-smb.sh`、`bin/build-usb-package.sh`
- feat(build): wire up client builds in bin/build-local.sh and document IP injection (Win7 A' 注入 + Win10+ 默认配置)
- feat(ci+docs): add smoke-test job to push-all-images.yml and 16-intranet-deployment.md
- feat(infra): add prepare-ubuntu-server.sh and 15-ubuntu-server-setup.md
- feat(intranet): integrate Win7 client distribution into intranet package (PR#2)
- feat(win7-compatibility): Win7 client support — VC++ 2013 + Zotero 5.0.96.3 (PR#1)

### Changed
- docs: split large files into chapters + add mkdocs.yml (PR#5) — 重新组织 docs/technical 与 docs/user-manual,统一 `XX-topic-name.md` 命名
- fix(package-for-intranet): use VER variable for manifest version field

### Documentation
- docs(pr#0): add PHP 8.5 Alpine build verification report

## [v0.1.0] - 2026-05-25

初始发布:
- Zotero dataserver (PHP 8.5) 内网部署
- Stream Server (WebSocket) 实时同步
- Admin 管理面板 (Laravel)
- Portal 用户门户 (Next.js)
- MinIO S3 对象存储
- Elasticsearch 全文搜索
- MariaDB + Redis + Memcached
- 一键部署脚本 `bin/deploy-intranet.sh`
- Win7/Win10+ 双客户端分发