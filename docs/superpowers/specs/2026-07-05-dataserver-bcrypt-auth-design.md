---
title: Dataserver bcrypt 迁移 + 专用 auth endpoint 设计稿
status: Draft（待用户审核）
date: 2026-07-05
branch: docs/restructure
author: brainstorming-session
related:
  - stack/dataserver/config/AdminController.php
  - stack/dataserver/config/routes.inc.php
  - stack/dataserver/dbconfig/www.sql
  - stack/webui/portal/app/api/auth/login/route.ts
  - stack/webui/portal/app/api/auth/register/route.ts
  - docs/notes/2026-07-05-portal-no-2fa-followups.md
  - docs/superpowers/specs/2026-07-05-portal-intranet-no-2fa-design.md (上游)
---

# Dataserver bcrypt 迁移 + 专用 auth endpoint 设计稿

## 1. 背景与目标

`docs/notes/2026-07-05-portal-no-2fa-followups.md` 列出 F-1（MD5→bcrypt）+ F-3（users.find 全表扫描）。两件事**天然联动**：都通过新增 dataserver 专用 auth endpoint 一并解决。

**现状:**
- `stack/dataserver/dbconfig/www.sql:27` —— `users.password char(40)` (MD5: 32 hex)
- `stack/dataserver/config/AdminController.php:177-178` —— `INSERT INTO users (..., password) VALUES (..., MD5(?))` 创建用户用 MD5
- `stack/dataserver/config/AdminController.php:229-256` —— `listUsers()` 仍 SELECT `u.password`（PR#9 commit 33c3bbe7 加的，让 portal 端能做 MD5 对比）
- `stack/webui/portal/app/api/auth/login/route.ts:33-39` —— portal 端用 `crypto.createHash('md5')` 客户端 hash + 拉全表 `users.find()`
- `stack/webui/portal/lib/api.ts:48-59` —— `getUserKeys(userId)` 二次调用取 apiKey

**双重问题:**
1. **无 salt MD5** + 客户端 hash —— 离线 rainbow table 攻击容易，client-side hash 违反 zero-trust
2. **portal 拉全表 + 接收 hash** —— 性能/隐私/secret 泄漏三重问题

**目标:**
- dataserver 接受 plain password（不 pre-hash），服务端 `password_hash(PASSWORD_BCRYPT)` 存，`password_verify()` 校验
- 自动迁移：旧用户首次成功登录后,服务端若发现 password 字段仍是 MD5 形式，自动重哈希升级
- 新增专用 `POST /api/auth/login` 端点 — 接受 `{username, password}`，返回 `{success, userID, apiKey}` one-shot
- portal 端 `login/route.ts` 改为调新 endpoint，**删除** `crypto.createHash('md5')` 全部逻辑与 `users.find()` 全部逻辑
- `listUsers()` 改为不 SELECT `u.password`（防 hash 暴露给 super-user 端点）
- 不动 Zotero API（`/users/:id/keys` 仍可独立调，备用通道保留）

**非目标:**
- 不引入其他 hash 算法（argon2/scrypt） —— 用 PHP 标准库的 bcrypt 已足够
- 不批量一次性迁移所有 MD5 用户 —— 仅按需 auto-migrate on first successful login（理由见 §7）
- 不重写 login 整体架构（OAuth/SSO）—— 范围限制
- 不动 admin 站点的 Laravel 2FA 配置

## 2. 方案选型

| 方案 | 简述 | 取舍 |
|---|---|---|
| **A. 新建 `/api/auth/login` + 改 createUser 用 bcrypt**（推荐） | dataserver 改造 + portal 调用新端点 + auto-migrate | 一并解决 F-1 + F-3 + rate-limit 可扩展；代码改动局限在两个 controller 文件 + portal 端 login route |
| B. 在 portal 端用 web crypto API 做 bcrypt | portal 单独 hash,服务端仍 MD5 | 不动 dataserver,但 portal 没法做 zero-trust 校验;且无 PHP 端 hash 升级通道 |
| C. 改用 argon2id via libsodium | 现代算法 | PHP 需要额外扩展（`libsodium-php`）;引入 runtime 依赖;argon2 vs bcrypt 对 2026 内网部署 ROI 不明显 |
| D. 强制每个用户重置密码 | UI 上大批量提示 | 运营负担大、用户体验差;admin-script 批量升级是次优备选 |

确认决策：方案 A。

## 3. 涉及文件清单

### 3.1 dataserver 改动（`stack/dataserver/`）

**修改:**
- `config/AdminController.php`
  - `createUser()` line 177-178: `MD5(?)` → `password_hash(?, PASSWORD_BCRYPT)` （PHP 标准库）
  - `listUsers()` line 231: 移除 `u.password` 从 SELECT；line 243: 移除 `'password' => $row['password']` 从 JSON 输出
  - 新增 public method `authLoginAction()`: 路由 handler (`/api/auth/login`),super-user gated（与 `users()` 相同的 `isSuper()` check）
  - 新增 private method `authenticate($username, $password)`: 业务核心 — `password_verify` 失败时尝试 MD5 fallback,命中时 `password_hash` 重哈希,返回 `array('userID' => $id, 'migrated' => true/false)` 或 `null`（401）
  - authLoginAction 内部:`authenticate()` 成功 → 调 `${dataserver.url}/users/{id}/keys` (Zotero API 端点) 取 apiKey → 返回 `{success, userID, apiKey}`

- `config/routes.inc.php` line 10-11 后:新增 `$router->map('/api/auth/login', ['controller' => 'Admin', 'action' => 'authLoginAction']);`

**新建:**
- 无（dataserver 是 PHP 无构建步骤）

**SQL 迁移:**
- `dbconfig/db_update.sh` 修改 — 在末尾追加 `ALTER TABLE users MODIFY password varchar(60) NOT NULL;`
  - 现有 MD5 32 hex 字符装得下 varchar(60) 完全无问题
  - bcrypt `$2y$10$...(22 chars salt + 31 hash)$` = 60 字符
  - 注意:`www.sql:27` 的 `char(40)` 也要同步改为 `varchar(60)`，避免全新部署时仍然限定 40 字符

### 3.2 portal 改动（`stack/webui/portal/`）

**修改:**
- `app/api/auth/login/route.ts`
  - 移除 `crypto.createHash('md5')` 调用（line 35-36）
  - 移除 `users.find((u) => u.username === ...)` 拉全表逻辑（line 22-25）
  - 改为调 `${dataserver.url}/api/auth/login` with body `{username, password}`,Bearer super-token
  - 接收响应 `{success, userID, apiKey}`,set session
  - 错误处理:401 → `{"error":"Invalid credentials"}`,其它 5xx → `{"error":"Login failed"}`
- `lib/api.ts` —— **不删** `getUserKeys()`(留作备用通道;新 endpoint 内部会用一次,然后 portal 不再直接调)
- `config.yaml` —— `dataserver.url` 保持（host 视角下 `http://localhost:8080` 或容器内 `http://dataserver:8080`）

**新建:**
- 无

**不修改:**
- `app/api/auth/register/route.ts` —— register 仍走 `POST /admin/users` (它接受 plain password,dataserver 自己 hash)
- `app/api/auth/logout/route.ts` —— 不涉及
- `app/page.tsx` / `app/portal/page.tsx` / portal 页面 —— 不涉及

### 3.3 文档

**修改:**
- `docs/notes/2026-07-05-portal-no-2fa-followups.md` — F-1 + F-3 段更新为 `[DONE 2026-07-05]`

**新建:**
- 无

## 4. API 契约（新 endpoint）

### 4.1 `POST /api/auth/login`

**Headers:**
- `Authorization: Bearer ${API_SUPER_TOKEN}` (与现有 admin 端点一致)
- `Content-Type: application/json`

**Request body:**
```json
{
  "username": "alice",
  "password": "plain-text"
}
```

**Response 200 (成功):**
```json
{
  "success": true,
  "userID": 42,
  "apiKey": "..."
}
```

**Response 401 (密码错或用户不存在):**
```json
{ "error": "Invalid credentials" }
```

**Response 403 (super token 缺/错):**
```json
{ "error": "Super user access required" }
```

**Response 400 (body 缺字段):**
```json
{ "error": "username and password required" }
```

**关键实现细节:**
- `password_verify($input, $storedHash)` 用于 bcrypt 校验
- **auto-migrate 逻辑**:`password_verify` 失败时,若 `$storedHash` 是 32 字符 hex (匹配 `/^[a-f0-9]{32}$/`),尝试 `hash_equals($storedHash, md5($input))` 校验 MD5;若通过则 `UPDATE users SET password = ? WHERE userID = ?` 用 `password_hash($input, PASSWORD_BCRYPT)` 升级,**不** return error。这是**核心迁移机制**。
- 现有 `createUser()` 用 MD5,register 流程立即触发:auto-migrate 在新 endpoint 跑,但 register 路径仍写入 MD5 —— **决策见 §6.4**

### 4.2 `POST /admin/users` (register 路径,不修改契约)

register 仍走这个 super-user 端点。`createUser` 内 `MD5(?)` → `password_hash(...)`。契约面 (`{userID, username, email, libraryID}`) 不变。

### 4.3 `GET /admin/users` (listUsers 路径)

不再返回 `password` 字段。契约面变更:从 `[userID, username, password, email, enabled]` → `[userID, username, email, enabled]`。

**breaking change 风险评估**:listUsers 的消费方 — `stack/admin/...` Laravel admin 站点不读 password 字段（其有自己用户管理）。`stack/webui/portal/...` 在 PR#9 改后**应当**不再读 password 字段（PR#9 重写 login route 时仍读 `user.password` MD5 比较,本次也改）。无人依赖 password 字段。

## 5. 数据迁移

### 5.1 SQL schema 变更

`ALTER TABLE users MODIFY password varchar(60) NOT NULL;`

**为什么不新增 `password_hash` 列?**
- 现有 `password` 列已存 MD5,改成 `varchar(60)` 即可同时容纳两种格式
- 无需修改任何 INSERT/SELECT (除 createUser)
- auto-migrate 一次完成,后续全部新格式

### 5.2 数据迁移路径

**`stack/dataserver/dbconfig/db_update.sh` 新增 step:**

```bash
# V3 → V4: extend password column for bcrypt
mysql ... -e "ALTER TABLE users MODIFY password varchar(60) NOT NULL;"
```

更新 `www.sql` 创建 schema (全新部署用):
```sql
`password` varchar(60) COLLATE utf8_bin NOT NULL,
```

### 5.3 应用层迁移 (auto-migrate on first successful login)

- 用户登录时,服务端检查 password 字段
- 若 `password_verify` 失败,**且** 字段是 32 hex chars,尝试 MD5 校验
- 若 MD5 校验成功,`password_hash($input, PASSWORD_BCRYPT)` 写入
- 这一行是**关键** — 用户无感升级

**风险:** 用户用错密码永远不触发升级,MD5 永远驻留。**接受这个限制**,理由:
- admin script 可一次性强制升级 (后续工作,不在本 PR)
- 用户只会在登录时升级,实际部署中不活跃用户占比低
- 错密码升级"反而不好" — 不知道真密码无法升级

**短中期用户可见性:**
- 新注册用户:创建时直接 bcrypt,无需 auto-migrate
- 现有登录用户(密码对):首次成功登录时升级,后续永远 bcrypt
- 长期不活跃用户:仍是 MD5,但 risk surface 仅为理论可能(数据库泄漏才暴露)

## 6. 关键决策表 (待用户拍板)

> 这是把"ask 1 question"合并到 spec 末尾供一次性决策。**用户审 spec 时回复 1-6 项即可**。

| # | 决策 | 建议默认 | 备选 |
|---|---|---|---|
| 6.1 | 新 endpoint 路径 | `/api/auth/login`（REST 风格，super-token gated） | `/admin/auth/login`（与现有 admin 命名空间一致） |
| 6.2 | auto-migrate 策略 | "首次成功登录时升级"（无感，渐进） | "admin 脚本一次性批量升级"（更彻底但需新工具） |
| 6.3 | 字段名 `password` 是否改名 | 保留 `password`（仅改 type 长度） | 改 `password_hash`（更精确但所有引用点更新） |
| 6.4 | `createUser` 现在用 bcrypt — 但 register 路径由 `createUser` 处理 | createUser 改为 `password_hash(?, PASSWORD_BCRYPT)` | 保持 MD5 写入,等 login 时 auto-upgrade（分裂数据） |
| 6.5 | `listUsers` 是否仍 super-gated | 保持 super-gated（不开放 list 给他方） | 改为 public（admin 站点可能需要） |
| 6.6 | rate limiting 是否在 F-1+F-3 范围 | **不在范围** —— 仅留 hook（如新 endpoint 内部计数）;完整 rate limit 留作 F-7 | 在新 endpoint 内实现 IP-based 限流（5/min/endpoint） |

**推荐 6.1–6.5 都按建议默认**，6.6 不在范围。

## 7. 认证流程（改后）

### 7.1 注册

```
Browser            POST /api/auth/register             Portal                    Dataserver
   │                  ────────────────────────►        │                             │
   │                                                  │  POST /admin/users          │
   │                                                  │ ─────────────────────────►  │
   │                                                  │  password_hash(plain)       │
   │                                                  │  INSERT users (bcrypt)      │
   │                                                  │ ◄─────── user JSON         │
   │                                                  │  POST /users/:id/keys       │
   │                                                  │ ◄─── apiKey                 │
   │                                                  │  set session: userId,       │
   │                                                  │    username, email, apiKey  │
   │ ◄── { success: true }                            │                             │
   ▼                                                  │                             │
   router.push('/portal')                             │                             │
```

### 7.2 登录（auto-migrate 路径）

```
Browser         POST /api/auth/login          Portal            Dataserver
   │              ─────────────────────►       │                    │
   │                                            │  POST /api/auth/login   │
   │                                            │ ────────────────────►  │
   │                                            │  authLoginAction()       │
   │                                            │  → authenticate()        │
   │                                            │    SELECT password,userID│
   │                                            │    WHERE username=?      │
   │                                            │  if password_verify()    │
   │                                            │    ok → userID           │
   │                                            │  elif password 是 32hex  │
   │                                            │    and md5(input)==stored│
   │                                            │    → UPDATE password     │
   │                                            │         = password_hash  │
   │                                            │    → userID (migrated)   │
   │                                            │  else → 401               │
   │                                            │  GET /users/{userID}/keys│
   │                                            │ ◄─── apiKey               │
   │                                            │ ◄─── {success,userID,    │
   │                                            │         apiKey}            │
   │                                            │  set session              │
   │ ◄── { success: true }                      │                            │
   ▼                                            │                            │
   router.push('/portal')                       │                            │
```

### 7.3 错密码（一致行为）

```
... 401 Invalid credentials → portal → { error: "Invalid credentials" }
```

## 8. 错误处理

| 场景 | 状态码 | 错误信息 |
|---|---|---|
| `username` 或 `password` 字段缺失 | 400 | `username and password required` |
| 用户不存在 | 401 | `Invalid credentials`（与密码错同错误，防枚举） |
| 密码错 (bcrypt 校验失败) | 401 | `Invalid credentials` |
| 密码错 (MD5 校验失败 — 旧用户错密码) | 401 | `Invalid credentials` |
| `password_verify` 内部错误 / DB 异常 | 500 | `Login failed` |
| 缺 super token | 403 | `Super user access required` |
| 用户无 API key | 500 | `No API key found` |

**注:** "用户不存在" 与 "密码错" 返回**相同** 401 + 错误信息,防 username enumeration。这是 OWASP 推荐做法。

## 9. 测试

### 9.1 单元测试

项目无单元测试框架（spec §1/§8.3 排除引入）。本 PR 沿用 PR#9 + F-4 模式：靠 `npx tsc --noEmit` + 端到端 e2e 验证。

### 9.2 端到端（e2e）测试扩展

在 F-4 引入的 `tests/e2e/portal.spec.ts` 中**追加**以下 step（不改已有 7 步）:

**8. 旧 MD5 用户登录自动升级到 bcrypt**
- 准备: 直接在 DB 中 `UPDATE users SET password = MD5('testpass') WHERE username = 'e2e_md5' LIMIT 1`
- step: 用 e2e_md5 / testpass 登录
- 断言: 登录成功,且 `SELECT password FROM users WHERE username = 'e2e_md5'` 返回的是 `$2y$10$...` 形式

**9. 错密码 401 (一致性)**
- 错密码提交
- 断言: 401 + `{"error":"Invalid credentials"}` body

**10. 缺 super token 403**
- 直接 curl dataserver `/api/auth/login` 缺 `Authorization: Bearer ...`
- 断言: 403 + `{"error":"Super user access required"}`

**11. listUsers 不再返回 password 字段**
- super token curl GET /admin/users
- 断言: 响应 JSON 中**无** `password` 键

### 9.3 部署验证

1. `docker build -t uniuu/zotprime-dataserver:v3.2.0 stack/dataserver/` 重建 dataserver 镜像
2. `docker compose up -d --force-recreate zotprime-dataserver` 拉新镜像
3. 应用 SQL schema 变更（dataserver 启动脚本会调 `db_update.sh`）
4. `docker compose up -d --force-recreate zotprime-portal` 拉新 portal 镜像
5. 跑 e2e 11/11 步骤
6. 现有用户用旧密码登录测试 auto-migrate 端到端

## 10. 风险

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| `password_hash` 慢（bcrypt cost 默认=10,~60ms/hash） | 低 | 登录响应慢 60ms | PHP 默认 cost=10,本项目用户量小可接受;如要更激进可调低到 cost=8 |
| auto-migrate 时 DB 写失败 | 极低 | 用户登录失败但不会数据损坏 | login 校验通过后做 migrate,失败仅 print log,不影响本次登录结果 |
| `listUsers` 移除 password 字段后,有调用方依赖 | 极低 | 调用方返回 null 报错 | grep 全仓库已确认:仅 PR#9 portal 端用过,本次 portal 端改造会一并改 |
| `password_hash` 不同 PHP 版本生成 hash 不可互验 | 极低 | 跨版本 hash 不兼容 | PHP 5.5+ 稳定;本项目 PHP 8.5 统一;跨大版本升级是另一回事 |
| register 路径中 `createUser` 改用 bcrypt 后,旧 setup.py 写 MD5 | 无 | — | 旧代码已不存在 (PR#9 改后唯一调用路径是 portal `/api/auth/register` → `createUser`) |
| SQL schema 变更失败 (column 已有非兼容数据) | 无 | — | 现有数据都是 MD5 (32 chars), 改 varchar(60) 完全兼容; bcrypt (60 chars) 也装得下 |

## 11. 实施步骤（概要）

> 详细步骤由 writing-plans 技能在 spec 审核通过后产出。

1. 新建 `feat/dataserver-bcrypt-auth` 分支
2. dataserver 改动:
   - 修改 `AdminController.php`: createUser 用 bcrypt, listUsers 移除 password 字段, 新增 authLogin() 私有方法
   - 修改 `routes.inc.php`: 新增 `/api/auth/login` 路由
   - 修改 `dbconfig/db_update.sh`: ALTER TABLE users MODIFY password varchar(60)
   - 修改 `dbconfig/www.sql`: 同步全新部署 schema
3. dataserver 重建 + 容器 recreate + 单元 curl 验证 endpoint
4. portal 改动:
   - `app/api/auth/login/route.ts` 重写: 调新 endpoint, 删 MD5 逻辑, 删 users.find
5. portal 重建镜像 + 容器 recreate + 端到端验证
6. e2e 测试扩展 4 个 step (8-11) + 跑通
7. 文档更新: F-1 + F-3 标记 DONE
8. commit + push + 提议 merge

## 12. 待用户确认的开放问题

1. **§6 决策表 6.1–6.6**（关键）
2. 是否要"auto-migrate 一次完成 vs 长期 MD5 残留"作为已知问题接受
3. 是否在 PR 描述里明确 breaking change (`listUsers` 不再返回 password 字段)
