# Portal 内网部署 + 移除 2FA — 后续跟进清单

> **来源:** PR#9 (`feat(portal): remove TOTP 2FA for intranet deployment`)
> **merge:** 2026-07-05 commit `66ad797c` · **tag:** `v0.3.0`
> **GitHub Issues 禁用:** `oneMuggle/zotprime` 已禁用 issues 端点,此文档作为 follow-up tracker

下列项目是 PR#9 review 阶段或后续 e2e 测试中发现的工作,均**不在 PR#9 范围**内(超出 spec §1 与 Global Constraints 的分支边界)。按优先级排序。

---

## F-1 [HIGH] security(dataserver): unsalted MD5 password hashing

**问题:** `stack/webui/portal/app/api/auth/login/route.ts` 用 `crypto.createHash('md5').update(password).digest('hex')`,与 dataserver 中存储的明文 MD5(`stack/dataserver/config/AdminController.php` users 表 `pass` 列)对比。

- 无 salt:相同密码 → 相同 hash
- MD5 在 2026 年已公认不安全
- 客户端 hash 不符合 zero-trust 原则(虽然此处只是 hash 而非明文)
- 与项目后续迁移到 bcrypt/argon2 的方向冲突

**前置:** PR#9 commit `33c3bbe7` 已经修了 password 字段不返回的问题(否则 MD5 都校验不了)。但**底层存储仍是无 salt MD5**。

**建议方案:**
1. dataserver 新增 `POST /api/auth/login`,接受 plain password,服务端做 hash 校验
2. 用户迁移:用户下次登录时,若发现仍是 MD5,自动 bcrypt 重哈希并更新
3. portal 端删除 `crypto.createHash('md5')` 全部逻辑
4. `users.pass` 字段类型与长度需扩展(`$2y$...` ≈ 60 字符)

**优先级:** HIGH — 阻塞下一个 portal 安全审计

**关联:** Issue track 失败(GitHub disabled),本地留档

---

## F-2 [HIGH] ops(deploy): 重建外部 portal 镜像

**问题:** PR#9 已合并,但当前 docker container `zotprime-zotprime-portal-1` 仍跑 `uniuu/zotprime-portal:v3.2.0`(旧代码,带 2FA)。本仓库无 portal Dockerfile(在外部 build pipeline 内,不在 stack/ 内可见)。

**行动项:**
1. 外部 build pipeline 重建 `uniuu/zotprime-portal` 镜像并 push 新 tag(如 `v0.3.0` 配套)
2. 本仓库 `.env`:`VER=v0.3.0`(或对应 tag)
3. `docker compose --profile portal up -d zotprime-portal` 拉新镜像
4. 验证:浏览器访问 `http://SERVER_IP:3045/`,登录**无需** 6 位码,直接进 `/portal`

**关联 dataserver 镜像:** 已在 PR#9 步骤内 rebuild(commit `33c3bbe7` 触发 container restart),不再需要外部 action

**优先级:** HIGH — **merge 后 portal 仍在生产跑旧代码**,直至该清单完成

---

## F-3 [MEDIUM] perf(dataserver): login 全表扫描

**问题:** `login/route.ts` 通过 `GET /admin/users` 拉**整个用户表**到 portal,然后 `users.find(u => u.username === username)`:

```ts
const users = await response.json();
const user = users.find((u: any) => u.username === username);
```

**影响:**
1. **性能:** 每次登录拉 N 个用户记录 + JSON 解析
2. **隐私泄漏:** portal 进程拿得到所有用户的 `userID + email + enabled`;portal 不需要这些
3. **MD5 hash 暴露:** 即使 super-token gated,login 也不应让 portal 看到其他用户的 password hash

**建议方案:** 与 F-1 联动 —— 直接引入 `POST /api/auth/login`,portal 给 plain password,dataserver 自己校验并返回 `{ success, userID, apiKey }`,portal 永远拿不到 list-all-users。

**优先级:** MEDIUM — 性能影响小规模不显著,但**安全/隐私侧必须修**

---

## F-4 [MEDIUM] test(portal): 引入 Playwright E2E

**背景:** PR#9 实施期间发现:
- 项目无 jest/vitest 配置(spec §1/§8.3 排除)
- 端到端测试只能依赖 curl + 手工浏览器
- **Task 7 发现的 dataserver pre-existing bug 就是因为没有自动化测试才漏到运行时才发现**

**建议方案:** 对 `docs/user-manual/50-portal-intranet.md` 中 7 步使用流程写 Playwright 脚本:

1. 访问 `/` 显示首页
2. 点 Sign In → `/login` 表单
3. 注册新用户 → 直接到 `/portal`
4. 退出登录 → 回到 `/`
5. 用刚注册账号重新登录 → 直接到 `/portal`
6. 清 cookie 访问 `/portal` → 重定向 `/login`
7. 5 次错误密码 → rate limiting (HTTP 429)

**实施细节:**
- Playwright + chromium,加入 CI(smoke-test job)
- 用 `bin/deploy-intranet.sh` 起本地 stack 后跑测试
- 测试用 docker compose ephemeral 容器,避免污染真实 dataserver

**优先级:** MEDIUM — 已经能工作,但缺乏 PR review 抗回归手段

---

## F-5 [LOW] chore(portal): 删除 dead-code `types/zotero-api-client.d.ts`

**问题:** `stack/webui/portal/types/zotero-api-client.d.ts` 在仓库从未被引用。grep 验证:`grep -r 'zotero-api-client' app/ lib/ types/` 仅文件本身命中。该文件是 ambient module declaration,无 runtime 影响,但仍是 dead code。

**建议方案:**
- 删除 `stack/webui/portal/types/zotero-api-client.d.ts`
- 同时考虑将 `types/index.ts` 拆为命名文件(`types/user.ts` / `types/session.ts` / `types/zotero.ts`)

**优先级:** LOW — 纯 cleanup

---

## F-6 [LOW] chore(portal): 清理未引用 deps `bcrypt` / `@types/bcrypt` / `@types/nodemailer`

**背景:** PR#9 显式保留 bcrypt 系列在 package.json(spec §1: 不清理 package.json 中已存在但未引用的 deps)。

**问题:**
- 占 `node_modules` 体积
- 扩大 security audit 表面(transitive deps 都潜在 CVE)
- lockfile 膨胀

**建议方案:**
1. grep 全仓库确认无引用后 `npm uninstall bcrypt @types/bcrypt @types/nodemailer`
2. 同时审计其它未引用依赖
3. 使用 `overrides` 字段锁住关键 transitive deps 版本

**优先级:** LOW

---

## 附录: PR#9 已完成的相邻修复

虽然 PR#9 范围限于"删除 2FA",但 task 6/7 阶段额外修了:

- 14 个 pre-existing lint 错误(`any`→`unknown`, `require()`→`import`, import 顺序)
- pre-existing dataserver bug(`/admin/users` 不返回 password 字段导致 login 永远 401)
- trailing newline 修复(2 个文件)

这些都在 `feat/portal-intranet-no-2fa` 的 9 commits + 1 dataserver fix commit 中。

---

**文档维护:** 当任一 follow-up 完成时,删除对应编号段并在 ledger 加 1 行记录完成。
