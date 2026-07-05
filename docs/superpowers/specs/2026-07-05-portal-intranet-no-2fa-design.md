---
title: ZotPrime Portal 内网部署 + 移除二维码 2FA 设计稿
status: Draft（待用户审核）
date: 2026-07-05
branch: docs/restructure
author: brainstorming-session
related:
  - stack/webui/portal/
  - docker-compose.yml
  - docs/intranet-deployment.md
---

# ZotPrime Portal 内网部署 + 移除二维码 2FA 设计稿

## 1. 背景与目标

ZotPrime 当前 Portal 网页门户（`stack/webui/portal/`，Next.js 16 + React 19 + iron-session）部署在公网/混合网络时，强制了"用户名密码 + TOTP 二因素验证（Google / Microsoft Authenticator 二维码）"：

- 注册时立即生成 TOTP secret 与 QR 码，写入 `data/db.json`
- 登录成功后将用户重定向到 `/verify` 页面，必须输入 6 位 TOTP 码才能进入 `/portal`
- `app/api/auth/login/route.ts` 还会拒绝任何**没有** TOTP 记录的用户（即每个用户在第一次登录前必须先经过 verify 流程）

在内网部署场景下，这一要求存在三个问题：

1. **每台终端都要装 Authenticator App**：内网用户机器往往没有/不允许装第三方 App
2. **二维码数据需要从 Google Charts / 服务器拉取**：与服务端 `qrcode` 库无关，但用户体验上仍依赖外部 App
3. **公网 2FA 是为对抗钓鱼/凭据泄露而设**，内网环境本身可信，再加一层 2FA 反而推高运维负担而无明显收益

`docker-compose.yml` 中的 `zotprime-portal` 服务（端口 3045）已具备内网部署基础（依赖 dataserver、走内部子网、env 注入 secret），本次改动的核心只动 Portal 子项目内的认证层。

**目标：**

- Portal 支持在内网环境部署，访问 `http://SERVER_IP:3045/`，HTTP（非 HTTPS）正常工作
- 移除二维码 Authenticator 强制二因素验证，改为"用户名 + 密码"单一登录
- 注册成功立即进入 `/portal`（与登录一致）
- 保留 rate limiting 防爆破，避免内网场景下弱口令风险放大
- 不动 `stack/admin/`（admin 是 Laravel + 端口 8182 的独立站点）
- 不动 `stack/dataserver/`、`stack/webui/admin/` 等其它容器

**非目标：**

- 不引入新的认证方式（SSO、邮箱验证码、LDAP 等）
- 不调整 portal 的功能页面（groups / item 详情）
- 不调整 admin 站点的 Laravel 2FA 配置
- 不清理 `package.json` 中已存在但未引用的 `bcrypt` / `@types/nodemailer` / `@types/bcrypt`（避免扩大 PR 范围）
- 不引入单元测试框架（项目当前无 jest/vitest 配置；编译/lint 验证足够）

## 2. 方案选型

调研与三方案对比后，**选用方案 A：彻底删除 TOTP 代码**：

| 方案 | 简述 | 取舍 |
|------|------|------|
| **A 彻底删除 TOTP（推荐）** | 删除 `lib/totp.ts` / `lib/db.ts` / `app/verify/*` / `verify route`；登录成功即进入 Portal | 最彻底、与用户"不要二维码 Authenticator 等验证"措辞完全吻合；代码量净减少 |
| B 保留可重新启用的开关 | 在 `config.yaml` 加 `enable_2fa: false`；关闭时跳过 verify 步骤 | 向后兼容性好，但保留死代码与未维护路径，与"YAGNI"原则冲突 |
| C 代码不动，运行时绕过 | login route 加 if 分支绕过 totp 检查 | 最快改完，但留有大量未使用的 totp 周边代码（lib/db.ts、qrcode 依赖、Session 字段），长期不健康 |

确认决策：

- 用户选择**方案 A**
- 注册流程同步简化——用户选择"注册后立刻进 Portal"
- TOTP 数据（`data/db.json` 中的 `totpSecrets` 数组）——用户选择"现在就删掉 TOTP 相关代码"，运行时不再读写

## 3. 涉及文件清单

### 3.1 删除（4 个文件）

| 路径 | 原因 |
|---|---|
| `stack/webui/portal/lib/totp.ts` | TOTP 生成 / 验证 / QR 生成全部功能 |
| `stack/webui/portal/lib/db.ts` | lowdb 单文件数据库只为 totpSecrets 服务 |
| `stack/webui/portal/app/verify/page.tsx` | QR 扫描 + 6 位码表单页面 |
| `stack/webui/portal/app/api/auth/verify/route.ts` | POST `/api/auth/verify` 验证入口 |

同时清理空目录：

- `stack/webui/portal/app/verify/` —— 文件删除后该目录变空
- `stack/webui/portal/app/api/auth/verify/` —— 文件删除后该目录变空
- `stack/webui/portal/data/` —— 内含旧的 `db.json`，文件一并删除（运维可选步骤，因为 db.ts 删除后不再被读取，文件只是占空间）

### 3.2 修改（7 个文件）

**`stack/webui/portal/app/api/auth/login/route.ts`**

- 移除 `getTOTPSecret` / `generateTOTPUri` / `generateQRCode` 引用
- 移除 `"TOTP not configured"` 检查分支（line 41-42）
- 登录成功直接 `session.apiKey = ...`，**不再**对 `session.totpSecret` / `session.totpVerified` 赋值
- 响应改为 `{ success: true }`

**`stack/webui/portal/app/api/auth/register/route.ts`**

- 移除 `generateTOTPSecret` / `generateTOTPUri` / `generateQRCode` / `setTOTPSecret` 调用
- 创建用户 + API key 后，直接 `session.apiKey = apiKey` 并保存
- 响应改为 `{ success: true }`

**`stack/webui/portal/app/login/page.tsx`**

- 移除 `if (result.showQR) { sessionStorage.setItem('totp', ...) }`
- `router.push('/portal')`（登录成功即跳转，不再 `/verify`）
- 由于响应不再返回 `qrCode/secret/showQR`，`const result = await response.json()` 可以移除（仅保留 `await response.text()` 或丢弃 response.json 仅做 ok 检查）

**`stack/webui/portal/app/register/page.tsx`**

- 移除 `sessionStorage.setItem('totp', ...)` 与 `router.push('/verify')`
- 注册成功后 `router.push('/portal')`
- 由于响应不再返回 `qrCode/secret`，`const result = await response.json()` 可以移除

**`stack/webui/portal/types/index.ts`**

- `SessionData` 移除 `totpSecret?: string` 与 `totpVerified?: boolean` 字段
- `LoginData` / `RegistrationData` 的 `captchaToken` 字段**保持原状**（不在本次改动范围）

**`stack/webui/portal/package.json`**

`dependencies` 移除：

- `otpauth` — 仅 `lib/totp.ts` 使用
- `qrcode` — 仅 `lib/totp.ts` 使用
- `lowdb` — 仅 `lib/db.ts` 使用

`devDependencies` 移除：

- `@types/qrcode`

**`stack/webui/portal/.gitignore`**

原已有 `data/` 忽略；现在 `data/db.json` 也不再生成，配置无需变更。

### 3.3 docker-compose.yml — **无需修改**

`docker-compose.yml` 第 271-293 行已包含 `zotprime-portal` 服务，内网部署所需的关键能力已具备：

- `3045:3000` 端口映射 ✓
- `depends_on` zotprime-dataserver ✓
- env 注入 `PORTAL_SESSION_SECRET` / `API_SUPER_TOKEN` / `SECURE_COOKIES` ✓
- 内部子网 `ipv4_address: 10.5.5.14` ✓
- `restart: always` ✓
- `profiles: ["portal"]` —— 默认不会随 `docker compose up` 启动，需要显式 `docker compose --profile portal up`

内网 HTTP（非 HTTPS）需要 `SECURE_COOKIES=false`；该项已通过 `lib/session.ts` 中的 `process.env.SECURE_COOKIES !== 'false'` 表达，由 env 控制。

### 3.4 环境配置（部署时检查）

`.env` 中至少需要：

```
PORTAL_SESSION_SECRET=<32+ 字符随机字符串>
API_SUPER_TOKEN=<与 dataserver API_SUPER_TOKEN 一致>
SECURE_COOKIES=false         # 内网 HTTP
```

这三项已在 `bin/deploy-intranet.sh` 部署脚本中处理，本次不修改；运维确认 `.env` 实际值即可。

### 3.5 用户手册 — **新增一节**

在 `docs/user-manual/` 现有章节下补一节"Portal 内网部署"：

- 端口 3045 的访问方式
- `SECURE_COOKIES=false` 的解释（HTTP 内网）
- 登录/注册流程（无 2FA）
- 旧部署残留 `data/db.json` 的清理命令：`rm -f stack/webui/portal/data/db.json`（可选）

具体章节文件名：`docs/user-manual/50-portal-intranet.md`（沿用现有编号 + 一句话简介风格）。

## 4. 认证流程（改后）

### 4.1 注册

```
Browser                POST /api/auth/register         Portal                   Dataserver
   │                  ────────────────────────►        │                             │
   │                                                  │  POST /admin/users           │
   │                                                  │ ─────────────────────────►  │
   │                                                  │ ◄─────── user JSON          │
   │                                                  │  POST /users/:id/keys        │
   │                                                  │ ─────────────────────────►  │
   │                                                  │ ◄── apiKey                   │
   │                                                  │  set session:                │
   │                                                  │    userId, username, email,  │
   │                                                  │    apiKey                    │
   │ ◄── { success: true }                            │                             │
   │                                                  │                             │
   ▼                                                  │                             │
   router.push('/portal')                             │                             │
```

### 4.2 登录

```
Browser                POST /api/auth/login            Portal                   Dataserver
   │                  ─────────────────────►          │                             │
   │                                                  │  GET /admin/users (Bearer)   │
   │                                                  │ ─────────────────────────►  │
   │                                                  │ ◄───── users[]              │
   │                                                  │  计算 md5(password)         │
   │                                                  │  对比 user.password         │
   │                                                  │  GET /users/:id/keys        │
   │                                                  │ ─────────────────────────►  │
   │                                                  │ ◄── apiKey                   │
   │                                                  │  set session: userId,       │
   │                                                  │    username, email, apiKey  │
   │ ◄── { success: true }                            │                             │
   │                                                  │                             │
   ▼                                                  │                             │
   router.push('/portal')                             │                             │
```

注意：旧的 login route 通过遍历所有用户找匹配账号（`users.find(u => u.username === username)`），是 dataserver 缺乏按用户名查询接口的临时方案；**本次不动**——超出范围。

### 4.3 注销

不变：`POST /api/auth/logout` → `session.destroy()`。

## 5. SessionData 类型变化

```typescript
// 改前
export interface SessionData {
  userId: number;
  username: string;
  email: string;
  apiKey: string;
  totpSecret?: string;
  totpVerified?: boolean;
}

// 改后
export interface SessionData {
  userId: number;
  username: string;
  email: string;
  apiKey: string;
}
```

`requireAuth()` 已只校验 `userId + apiKey`，无需同步改动；旧的 `session.totpVerified` 在 `session.destroy()` 时被一并清空，无残留风险。

## 6. 错误处理

`POST /api/auth/login` 仍按现状返回：

| 场景 | 状态码 | 错误信息 |
|---|---|---|
| 缺失字段 | 500 | `Login failed` |
| 用户不存在 | 401 | `Invalid credentials` |
| 密码错误 | 401 | `Invalid credentials` |
| API key 缺失 | 500 | `No API key found` |
| dataserver 不可达 | 401 | `Login failed` |

不变更错误结构，确保前端 `app/login/page.tsx` 的错误展示仍能工作。

`POST /api/auth/register` 维持现有错误流（错误信息透传）。

## 7. 数据迁移 / 清理

### 7.1 旧部署残留

旧 portal 容器内 `data/db.json` 中残留的 `totpSecrets` 字段在删除 `lib/db.ts` 后**不会被读取**，但仍占用磁盘。本次同步运维侧清理：

```
rm -f stack/webui/portal/data/db.json
```

此操作无副作用——文件结构完全由 `lib/db.ts` 自管理，删除后下次启动不再生成。

### 7.2 旧会话

所有浏览器中已签发的 iron-session cookie 包含 `totpSecret` / `totpVerified` 字段。

**结论**：`iron-session` 8.x 在反序列化 `SessionData` 时，对未声明字段做宽容忽略（即多余字段被静默丢弃），不会抛错。这是 iron-session 的默认契约，且已在 8.0.4 版本（项目当前使用）行为稳定。

如果将来 iron-session 升级到变更此默认行为的版本，需在 `getSession()` 末尾做一次性兜底：

```typescript
delete (session as any).totpSecret;
delete (session as any).totpVerified;
```

本次**不**为这一处加运行时迁移代码；按"需要时再加"原则处理。

如出现 iron-session 严格模式报错导致登录失败，**用户侧的临时处置是清浏览器 cookie**——cookie 名 `zotprime_session`（在 `lib/session.ts` 中定义），清掉即重新签发。

## 8. 测试与验证

### 8.1 编译/lint

```
cd stack/webui/portal
npm install           # 移除依赖后
npm run lint          # eslint
npm run build         # next build -- 输出 TS/打包错误
```

期望：无错。TS 严格模式下 `totpSecret` 字段被引用为 `unknown` 全部消失，应该一次过。

### 8.2 端到端（手工）

环境：本地 `docker compose --profile portal up`，访问 `http://localhost:3045/`

| 场景 | 预期 |
|---|---|
| 访问 `/` | 显示首页（Get Started / Sign In） |
| 点 Sign In → `/login` | 表单可填，二字段（username / password） |
| 提交注册（合法字段） | 直接进入 `/portal`，看到 "Your Groups"（首次无 group 时显示空提示） |
| 退出登录 | 回到 `/` |
| 输入已注册用户名密码登录 | 直接进入 `/portal` |
| 访问 `/portal`（未登录） | 重定向 `/login` |
| 访问 `/verify` | 应当返回 404（页面已删除） |
| 5 次错误密码登录 | 应触发 rate limiting（`config.yaml` 已有定义） |

### 8.3 不做的事

- 不引入 jest / vitest 单元测试
- 不引入 Playwright E2E 自动化（项目当前无此层）
- 不引入 docker 集成测试（portal 容器本身在 `docker-compose.yml` 已声明，重新 `docker compose build` + 启停即可）

## 9. 风险与回滚

| 风险 | 概率 | 影响 | 回滚方式 |
|---|---|---|---|
| 旧浏览器 cookie 触发 iron-session 报错 | 低 | 单用户登录失败 | 清 cookie 即可；如大规模，再补运行时迁移补丁 |
| `package.json` 移除依赖后 npm 解析失败 | 极低 | 构建失败 | `npm install` 重装；如保留 `otpauth` 也无功能影响 |
| 容器镜像未重建 | 中 | 旧代码仍跑 | `docker compose --profile portal build zotprime-portal` 后再 up |
| `SECURE_COOKIES=true`（默认值）下用 HTTP 访问 | 中 | cookie 不下发 | `.env` 改 `SECURE_COOKIES=false` |
| 注册返回无 qrCode，前端若 cache 旧 schema | 低 | 控制台 warning | 浏览器侧无效 |

回滚策略：本次改动是一个新分支 `feat/portal-intranet-no-2fa`（沿用 git-workflow 规范），如上线后发现问题，回滚 PR 即可。Portal 容器 vs. dataserver 之间无 API 契约变更，dataserver 端无需同步回滚。

## 10. 实施步骤（概要）

> 详细实施计划由 writing-plans 技能在 spec 审核通过后产出。

1. 建 feature 分支 `feat/portal-intranet-no-2fa`
2. 删除 TOTP 相关 4 文件 + 3 个空目录
3. 改 4 个路由 / 页面源文件 + 1 个类型文件 + 1 个 `package.json`
4. `npm install` + `npm run lint` + `npm run build` 三连验证
5. 本地 `docker compose --profile portal build` 重建镜像
6. 起容器，做端到端验证（注册 / 登录 / 已登录访问 `/portal` / 注销）
7. 部署文档 / 用户手册新增 `docs/user-manual/50-portal-intranet.md`
8. commit → push → PR

## 11. 待用户确认的开放问题

> 当前文档基于用户在线澄清答复撰写，没有遗留开放问题。

- ~~认证方案：~~ ✓ 用户选"仅用户名+密码登录"
- ~~TOTP 数据处理：~~ ✓ 用户选"现在就删掉 TOTP 相关代码"
- ~~注册流程：~~ ✓ 用户选"注册后立刻进 Portal"
