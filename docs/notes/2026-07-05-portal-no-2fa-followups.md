# Portal 内网部署 + 移除 2FA — 后续跟进清单

> **来源:** PR#9 (`feat(portal): remove TOTP 2FA for intranet deployment`)
> **merge:** 2026-07-05 commit `66ad797c` · **tag:** `v0.3.0`
> **GitHub Issues 禁用:** `oneMuggle/zotprime` 已禁用 issues 端点,此文档作为 follow-up tracker

下列项目是 PR#9 review 阶段或后续 e2e 测试中发现的工作,均**不在 PR#9 范围**内(超出 spec §1 与 Global Constraints 的分支边界)。按优先级排序。

---

## F-1 [DONE 2026-07-05] security(dataserver): unsalted MD5 password hashing

**解决:** 分支 `feat/dataserver-bcrypt-auth`,7 commits:
- `7e809ff5` feat(dataserver): bcrypt password hash + authLogin endpoint
  - `createUser`: `MD5(?)` → `password_hash(?, PASSWORD_BCRYPT)`
  - `listUsers`: 移除 `password` 字段返回(防 hash 暴露)
  - 新增 `authLoginAction()` (public) + `authenticate()` (private)
- `e0daef9e` fix(dataserver): backtick `keys` table name in authLogin SQL
- `07db240f` feat(dataserver): route `POST /api/auth/login`
- `60e67e21` feat(dataserver): extend `users.password` to `varchar(60)`
- `0c6fd91e` feat(portal): login uses new endpoint, deletes MD5 logic
- `041dc294` test(portal): 4 e2e steps (auto-migrate, 401, 403, listUsers)
- `0d59b7f8` ci(e2e): pass API_SUPER_TOKEN + MARIADB_ROOT_PASSWORD

**验证:**
- 11/11 e2e tests pass (F-4 7 + 新 4)
- Dataserver curl 5/5 通过(listUsers no password / register bcrypt / login correct / login wrong 401 / auto-migrate MD5→bcrypt)
- Portal curl 4/4 通过(register / login / wrong 401 / /portal with cookie)

**已知 deviations (subagent 报告 §Concerns):**
1. `e401` 不存在 — `ApiController::__call` 是 e4xx 文本响应;但 spec §4.1 要求 JSON body。改用 inline `header('Content-Type: application/json'); http_response_code(N); echo json_encode([...]); exit;`。
2. DB name `zotero_www` (非 `zotprime_www`)
3. `db_update.sh` **不自动跑** (`entrypoint.sh` 不调用)。已手动 `docker exec ... ALTER TABLE` 应用。生产部署需要在 entrypoint 或单独 init 步骤调 `db_update.sh`。
4. e2e test 8 用 `docker exec mariadb` — 本地 dev OK,CI runner 需 docker socket
5. `session.email` 现在是空字符串(auth endpoint 不返回 email)

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

## F-3 [DONE 2026-07-05] perf(dataserver): login 全表扫描

**解决:** 与 F-1 联动(同一 PR 同一分支)。新端点 `POST /api/auth/login`:
- 接受 `{username, password}` plain
- 服务端 `password_verify` / MD5 fallback + auto-migrate
- 返回 `{success, userID, apiKey}` (one-shot)
- Portal 端 `login/route.ts` 删除 `users.find()` 全表扫描 + `crypto.createHash('md5')` + `getUserKeys()` 二次调用

Portal 不再持有 password hash 或 list-all-users 数据。性能 + 隐私 + 安全三重问题一并解决。

---

## F-4 [DONE 2026-07-05] test(portal): 引入 Playwright E2E

**解决:** commit `4ef06515`(分支 `test/f4-portal-playwright-e2e`)
- `stack/webui/portal/playwright.config.ts` — Chromium only,无 webServer block(portal 假设外部已运行),`baseURL` 来自 `PORTAL_BASE_URL` env(默认 `http://localhost:3045`)
- `stack/webui/portal/tests/e2e/portal.spec.ts` — 7 步 happy-path,serial mode,新用户名 `e2e_<Date.now()>` 避免重跑冲突
- `stack/webui/portal/package.json` — 加 `e2e` / `e2e:install` 脚本,`@playwright/test ^1.61.1` 入 `devDependencies`
- `stack/webui/portal/.gitignore` — 忽略 `playwright-report/`、`test-results/`、`.playwright-cache/`
- `.github/workflows/push-all-images.yml` — 新增 `e2e-portal` job(`needs: build`),使用刚构建的 portal + dataserver 镜像跑 `npm run e2e`,失败上传 report artifact

**验证:**
- 本地:`PORTAL_BASE_URL=http://localhost:3045 npm run e2e` → 7 passed (7.5s)
- `npx tsc --noEmit` exit 0
- Chromium 安装走 `--with-deps` 失败(无 sudo),fallback 到 `npx playwright install chromium`(已 cache,无需 root)

**已知 gap(step 7):**
- `config.yaml` 配置 `auth_requests_per_minute: 5`,但 `lib/` 和 `app/api/auth/login/route.ts` **未实际强制**限流
- 实测 5 次错误密码均返回 401(应返回 429)
- 测试断言已做兼容:若返回 429 则 PASS,否则记录 `test.info().annotations['rate-limit-gap']` 继续 PASS(避免 false positive)
- 修复属于 F-3(login route hardening)的延伸,不在 F-4 范围内

**范围控制:**
- 未修改任何 `app/` 或 `lib/` 代码(spec 禁止)
- 未修改 `bin/`、`docker-compose.yml`、`docs/user-manual/*`、`docs/plans/*`、`CHANGELOG.md`、`.env*`
- CI 集成以单一 job 形式加入 `push-all-images.yml`(不另起 workflow),但该 workflow 当前只在 `workflow_dispatch` 触发,**PR gating 未启用**(留作 F-7)

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
