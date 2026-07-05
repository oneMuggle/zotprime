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

## F-2 [DONE 2026-07-05] ops(deploy): 重建外部 portal 镜像

**解决:** 实际 portal Dockerfile 在仓库内 `stack/webui/webui.Dockerfile`(非 `stack/webui/portal/` 子目录)。`bin/build-local.sh` 第 [13/13] 步触发 build,默认 tag `v3.2.0`。

**已完成:**
1. `DOCKER_BUILDKIT=1 docker build -f stack/webui/webui.Dockerfile -t uniuu/zotprime-portal:v3.2.0 -t uniuu/zotprime-portal:v0.3.0 stack/webui/`
2. `docker compose --profile portal up -d --force-recreate zotprime-portal` 拉新镜像替换运行中容器
3. 端到端验证 9/9 通过:
   - `/`, `/login` → 200
   - `/verify` → **404**(新代码生效)
   - `/portal` 未登录 → 307 重定向 `/login`
   - `POST /api/auth/register` 新用户 → `{"success":true}` 200
   - `POST /api/auth/login` 同用户 → **`{"success":true}` 200**(C-1 dataserver fix 协同生效)
   - `POST /api/auth/login` 错密码 → 401 `{"error":"Invalid credentials"}`
   - `GET /portal` 带 cookie → 200 + 8863 bytes,内容含 "ZotPrime" / "Welcome" / "Your Groups"
4. 镜像 tag:v3.2.0(主)+ v0.3.0(v0.3.0 release 别名,同一 SHA `78f15...`)

**修改的 .env:** 无(`.env` 的 `VER=v3.2.0` 保持,portal 镜像同名 tag 不变)

**反思:** 之前误判 "portal 镜像在外部 build pipeline 重建"。事实是 portal Dockerfile 一直在本仓库,只是路径是 `stack/webui/webui.Dockerfile` 而非 `stack/webui/portal/Dockerfile`。`bin/build-local.sh` 的 [13/13] 步已经写好 build 流程。重 build + 端到端验证在 PR#9 merge 后 5 分钟内完成。

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

## F-5 [DONE 2026-07-05] chore(portal): 删除 dead-code `types/zotero-api-client.d.ts`

**解决:** commit `37fda0e2`
- 1 个 dead-code 文件删除
- grep 验证前后一致:无任何源文件 import zotero-api-client
- 不考虑 types/index.ts 拆分了(范围控制,YAGNI 友好)

## F-6 [DONE 2026-07-05] chore(portal): 清理未引用 deps `bcrypt` / `@types/bcrypt` / `@types/nodemailer`

**解决:** commit `37fda0e2` (与 F-5 同 commit)
- `npm uninstall bcrypt @types/bcrypt @types/nodemailer`
- grep 验证:portal 中无任何 import
- package-lock.json 减少 54 行
- rebuild portal 镜像 (新 SHA: 78f15...);端到端验证 register/login happy path 通过

---

## 附录: PR#9 已完成的相邻修复

虽然 PR#9 范围限于"删除 2FA",但 task 6/7 阶段额外修了:

- 14 个 pre-existing lint 错误(`any`→`unknown`, `require()`→`import`, import 顺序)
- pre-existing dataserver bug(`/admin/users` 不返回 password 字段导致 login 永远 401)
- trailing newline 修复(2 个文件)

这些都在 `feat/portal-intranet-no-2fa` 的 9 commits + 1 dataserver fix commit 中。

---

**文档维护:** 当任一 follow-up 完成时,删除对应编号段并在 ledger 加 1 行记录完成。
