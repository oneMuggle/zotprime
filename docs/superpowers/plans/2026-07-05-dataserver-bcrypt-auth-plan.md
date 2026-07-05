# Dataserver bcrypt 迁移 + 专用 auth endpoint 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 dataserver users 表的 password 存储从 MD5 迁移到 bcrypt,新增专用 `/api/auth/login` 端点替换 portal 端的 `users.find()` 全表扫描;portal 端 `login/route.ts` 改调新端点,删除 `crypto.createHash('md5')` 全部逻辑。

**Architecture:** 三层改动:①dataserver (PHP) — `createUser` 改用 `password_hash`、新增 `authLoginAction` + `authenticate` 私有方法、`listUsers` 移除 password 字段、SQL schema 扩到 `varchar(60)`;②portal (Next.js) — `login/route.ts` 改调新端点;③e2e — 追加 4 个 Playwright step 覆盖 auto-migrate + 401 + 403 + listUsers 无 password 字段。

**Tech Stack:** PHP 8.5 (dataserver) · Next.js 16.1 + iron-session 8.0.4 (portal) · MySQL · Playwright

## Global Constraints

- **Spec 文件**:`docs/superpowers/specs/2026-07-05-dataserver-bcrypt-auth-design.md` —— 本 plan 的唯一真相源,所有值/错误信息/API 契约 verbatim
- **§6 决策表已确认** (用户 OK): 6.1 `/api/auth/login`、6.2 首次成功登录时升级、6.3 字段名保留 `password`、6.4 `createUser` 改用 `password_hash`、6.5 `listUsers` 仍 super-gated、6.6 rate limiting 不在范围
- **改动范围严格限制**:
  - dataserver: `config/AdminController.php` + `config/routes.inc.php` + `dbconfig/db_update.sh` + `dbconfig/www.sql` —— 仅此 4 文件
  - portal: `app/api/auth/login/route.ts` + `tests/e2e/portal.spec.ts` —— 仅此 1-2 文件
  - 文档: `docs/notes/2026-07-05-portal-no-2fa-followups.md`
  - 不动: `bin/`、`docker-compose.yml`、admin、Laravel、Zotero 客户端
- **不引入** 新 npm 包、新 PHPUnit、新 deps
- **不修改** working tree 中 pre-existing 改动 (bin/deploy-intranet.sh, docker-compose.yml, .env.local.backup, CHANGELOG.md, docs/plans/*, docs/user-manual/40-client-features.md)
- **dataserver 容器重建后**,`db_update.sh` 自动跑(`ds.Dockerfile` 已配)
- **端到端验证**:dataserver 端用 curl(因为没 e2e 框架覆盖 PHP);portal 端用 Playwright(F-4 引入)
- **commit 规范**:conventional commits,scope 选 `dataserver` / `portal` / `docs`
- **分支命名**:`feat/dataserver-bcrypt-auth`,基于 `docs/restructure@e7ad8cfe`(最新)

## 文件结构

**修改 (dataserver):**
- `stack/dataserver/config/AdminController.php` (3 处: createUser 改 hash、listUsers 移除 password、新增 authLoginAction + authenticate)
- `stack/dataserver/config/routes.inc.php` (1 行新增: `/api/auth/login`)
- `stack/dataserver/dbconfig/db_update.sh` (末尾追加: ALTER TABLE)
- `stack/dataserver/dbconfig/www.sql` (line 27: char(40) → varchar(60))

**修改 (portal):**
- `stack/webui/portal/app/api/auth/login/route.ts` (完整重写,删 MD5 逻辑)
- `stack/webui/portal/tests/e2e/portal.spec.ts` (追加 4 step)

**修改 (文档):**
- `docs/notes/2026-07-05-portal-no-2fa-followups.md` (F-1 + F-3 段标记 DONE)

**新建:**
- 无

---

## Task 1: 建 feature 分支

**Files:** 仅 git 操作

- [ ] **Step 1: 确认 working tree 不污染** — `cd /home/fz/project/zotprime && git status --short`;应只显示 pre-existing untracked (bin/deploy-intranet.sh, docker-compose.yml, .env.local.backup, CHANGELOG.md, docs/plans/*, docs/user-manual/40-client-features.md)
- [ ] **Step 2: 基于 docs/restructure 建并切分支** — `git switch -c feat/dataserver-bcrypt-auth`
- [ ] **Step 3: 验证 spec 在分支里** — `ls docs/superpowers/specs/2026-07-05-dataserver-bcrypt-auth-design.md`

## Task 2: dataserver AdminController.php — createUser + listUsers + authLogin

**Files:**
- Modify: `stack/dataserver/config/AdminController.php`

**Interfaces (来自 spec §4.1 + §4.2 + §4.3):**
- `authLoginAction()` — public method, 路由 handler for `POST /api/auth/login`, super-user gated
- `authenticate($username, $password)` — private method, 返回 `['userID' => int, 'migrated' => bool] | null`(401)
- `authLoginAction()` 流程:读 body → 调 `authenticate()` → 成功后调 `${dataserver}/users/{id}/keys` 取 apiKey → 返回 `{success, userID, apiKey}` 或 401

- [ ] **Step 1: 修改 `createUser()` line 177-178**

把:
```php
$sql = "INSERT INTO users (username, password) VALUES (?, MD5(?))";
Zotero_WWW_DB_1::query($sql, [$username, $password]);
```

改为:
```php
$sql = "INSERT INTO users (username, password) VALUES (?, ?)";
$hashed = password_hash($password, PASSWORD_BCRYPT);
Zotero_WWW_DB_1::query($sql, [$username, $hashed]);
```

- [ ] **Step 2: 修改 `listUsers()` line 231 + line 243**

line 231 把:
```php
$sql = "SELECT u.userID, u.username, u.password, e.email, u.role
        FROM users u
        LEFT JOIN users_email e ON u.userID = e.userID
        WHERE u.role != 'deleted'
        ORDER BY u.userID";
```

改为(移除 `u.password`):
```php
$sql = "SELECT u.userID, u.username, e.email, u.role
        FROM users u
        LEFT JOIN users_email e ON u.userID = e.userID
        WHERE u.role != 'deleted'
        ORDER BY u.userID";
```

line 243 把:
```php
$users[] = [
    'userID'   => $row['userID'],
    'username' => $row['username'],
    'password' => $row['password'],
    'email'    => $row['email'],
    'enabled'  => ($row['role'] == 'normal'),
];
```

改为(移除 `'password' => ...`):
```php
$users[] = [
    'userID'   => $row['userID'],
    'username' => $row['username'],
    'email'    => $row['email'],
    'enabled'  => ($row['role'] == 'normal'),
];
```

- [ ] **Step 3: 在 `listUsers()` 之后追加 `authLoginAction()` + `authenticate()` 方法**

完整代码(append after `listUsers()` closing brace, before `deleteUser()`):

```php
public function authLoginAction() {
    if (!$this->permissions->isSuper()) {
        $this->e403("Super user access required");
    }
    
    if ($this->method != 'POST') {
        $this->e405();
    }
    
    try {
        $data = json_decode($this->body, true);
        
        if (!isset($data['username']) || !isset($data['password'])) {
            $this->e400("username and password required");
        }
        
        $result = $this->authenticate($data['username'], $data['password']);
        
        if (!$result) {
            $this->e401("Invalid credentials");
        }
        
        // Fetch user's API key from the Zotero API
        $sql = "SELECT key FROM keys WHERE userID = ? LIMIT 1";
        $key = Zotero_DB::valueQuery($sql, [$result['userID']]);
        
        if (!$key) {
            $this->e500("No API key found");
        }
        
        header('Content-Type: application/json');
        echo json_encode([
            'success' => true,
            'userID'  => $result['userID'],
            'apiKey'  => $key,
        ]);
        exit;
    }
    catch (Exception $e) {
        $this->handleException($e);
    }
}

private function authenticate($username, $password) {
    try {
        $sql = "SELECT userID, password FROM users WHERE username = ? AND role != 'deleted' LIMIT 1";
        $row = Zotero_WWW_DB_1::rowQuery($sql, [$username]);
        
        if (!$row) {
            return null;
        }
        
        $storedHash = $row['password'];
        $userID = $row['userID'];
        $migrated = false;
        
        // First try bcrypt
        if (password_verify($password, $storedHash)) {
            return ['userID' => $userID, 'migrated' => false];
        }
        
        // Fallback: if stored hash is 32 hex chars (legacy MD5), try MD5 + auto-migrate
        if (preg_match('/^[a-f0-9]{32}$/', $storedHash)) {
            $md5Hash = md5($password);
            if (hash_equals($storedHash, $md5Hash)) {
                // Auto-migrate to bcrypt
                $newHash = password_hash($password, PASSWORD_BCRYPT);
                $updateSql = "UPDATE users SET password = ? WHERE userID = ?";
                Zotero_WWW_DB_1::query($updateSql, [$newHash, $userID]);
                return ['userID' => $userID, 'migrated' => true];
            }
        }
        
        return null;
    }
    catch (Exception $e) {
        $this->handleException($e);
    }
}
```

注意:
- `Zotero_DB::valueQuery` 是 Zotero 分片 DB;`Zotero_WWW_DB_1::rowQuery` 是 www DB(单行 query)
- 如果项目里这两个方法名不同,subagent 应当 grep 项目其它 controller 学习正确 API 后再调用
- `e401` 可能不存在,需要 subagent 确认 ApiController 的 error helpers:`e400`, `e403`, `e405`, `e500` 是确认存在的;如果 `e401` 缺失,subagent 应添加它(模仿 e400 模式)或在 authLoginAction 中用 `http_response_code(401); exit;` 替代

- [ ] **Step 4: git diff 验证 3 处修改**

```bash
cd /home/fz/project/zotprime
git diff stack/dataserver/config/AdminController.php
```

预期:
- createUser line 177-178 改动
- listUsers line 231 SELECT 改动
- listUsers line 243 array 改动
- 末尾新增 `authLoginAction()` + `authenticate()` 约 60 行

- [ ] **Step 5: commit**

```bash
cd /home/fz/project/zotprime
git add stack/dataserver/config/AdminController.php
git commit -m "feat(dataserver): bcrypt password hash + authLogin endpoint

- createUser: MD5(?) -> password_hash(?, PASSWORD_BCRYPT)
- listUsers: 移除 password 字段返回 (防 hash 暴露给 super-user)
- 新增 authLoginAction() (public) + authenticate() (private):
  - password_verify() 失败 -> 32hex MD5 fallback -> 命中时 auto-upgrade
  - 成功返回 {success, userID, apiKey} (one-shot)

Refs: docs/superpowers/specs/2026-07-05-dataserver-bcrypt-auth-design.md"
```

## Task 3: dataserver 路由表

**Files:**
- Modify: `stack/dataserver/config/routes.inc.php`

- [ ] **Step 1: 在 line 13 后(line 12 是 `/admin/items`)插入新路由**

`stack/dataserver/config/routes.inc.php` line 12 后追加:

```php
$router->map('/api/auth/login', ['controller' => 'Admin', 'action' => 'authLoginAction']);
```

- [ ] **Step 2: git diff 验证**

```bash
cd /home/fz/project/zotprime
git diff stack/dataserver/config/routes.inc.php
```

预期: 1 行新增 (line 14)

- [ ] **Step 3: commit**

```bash
cd /home/fz/project/zotprime
git add stack/dataserver/config/routes.inc.php
git commit -m "feat(dataserver): route POST /api/auth/login -> Admin::authLoginAction"
```

## Task 4: SQL schema 变更

**Files:**
- Modify: `stack/dataserver/dbconfig/db_update.sh` (末尾追加 ALTER)
- Modify: `stack/dataserver/dbconfig/www.sql` (line 27: char(40) → varchar(60))

- [ ] **Step 1: 看 db_update.sh 当前内容**

```bash
cd /home/fz/project/zotprime
tail -30 stack/dataserver/dbconfig/db_update.sh
```

**注意:** 项目当前叫 `db_update.sh`,spec §3.1/§5.2 暗示可能是 `db_update2.sh` 或类似 — 实际名称以 working tree 为准

- [ ] **Step 2: 在 db_update.sh 末尾追加 ALTER**

```bash
# V3 -> V4: extend users.password from char(40) to varchar(60) for bcrypt (60 chars)
# bcrypt: \$2y\$10\$...(22 salt + 31 hash) = 60 chars. Existing MD5 (32 chars) also fits.
mysql ... -e "ALTER TABLE users MODIFY password varchar(60) NOT NULL COLLATE utf8_bin;"
```

实际 mysql 调用方式应模仿 db_update.sh 中现有的 ALTER/MIGRATION 行。**subagent 应当用项目已有的 mysql 调用风格**,不要硬编码 credentials。

- [ ] **Step 3: 修改 `www.sql` line 27**

line 27 把:
```sql
`password` char(40) COLLATE utf8_bin NOT NULL,
```

改为:
```sql
`password` varchar(60) COLLATE utf8_bin NOT NULL,
```

- [ ] **Step 4: 验证 SQL 语法合法性**

不需要真跑 MySQL,只要 grep 确认改动:
```bash
cd /home/fz/project/zotprime
grep -n "password.*varchar\|password.*char" stack/dataserver/dbconfig/www.sql stack/dataserver/dbconfig/db_update.sh
```

预期: `www.sql` 有 `password varchar(60)`,`db_update.sh` 有 ALTER TABLE

- [ ] **Step 5: commit**

```bash
cd /home/fz/project/zotprime
git add stack/dataserver/dbconfig/
git commit -m "feat(dataserver): extend users.password to varchar(60) for bcrypt

- ALTER TABLE users MODIFY password varchar(60) (auto-run on container start via db_update.sh)
- www.sql updated for fresh deployments

Existing MD5 (32 hex chars) fits in varchar(60); bcrypt (\$2y\$10\$... = 60 chars) also fits. No data loss."
```

## Task 5: dataserver 重建 + 容器 recreate + curl 验证

**Files:** 不修改源文件,仅运行

- [ ] **Step 1: 重建 dataserver 镜像**

```bash
cd /home/fz/project/zotprime/stack/dataserver
docker build -t uniuu/zotprime-dataserver:v3.2.0 -t uniuu/zotprime-dataserver:v0.3.0 -f ds.Dockerfile . 2>&1 | tail -10
```

预期: Successfully tagged,无 build error

- [ ] **Step 2: 重启 dataserver 容器**

```bash
cd /home/fz/project/zotprime
docker compose up -d --force-recreate zotprime-dataserver 2>&1 | tail -5
sleep 5
docker compose ps zotprime-dataserver
```

预期: status Up / running,新镜像 ID 不同于重建前

- [ ] **Step 3: 验证 schema 已 ALTER**

```bash
TOKEN=$(grep '^API_SUPER_TOKEN=' /home/fz/project/zotprime/.env | cut -d= -f2- | tr -d '"' | tr -d "'")
docker exec -i zotprime-zotprime-dataserver-1 mysql -u root -p"$(grep '^MARIADB_ROOT_PASSWORD=' /home/fz/project/zotprime/.env | cut -d= -f2- | tr -d '"' | tr -d "'")" -e "SHOW COLUMNS FROM users WHERE Field='password';" zotprime_www 2>&1 | tail -10
```

预期:`Type: varchar(60)`

如果容器内没 mysql 客户端,改用:从 host 端口 `localhost:3307` 查 (MARIADB 是 host 端口 3306 → 容器内 3306)

```bash
mysql -h 127.0.0.1 -P 3306 -u root -p"<MARIADB_ROOT_PASSWORD>" -e "SHOW COLUMNS FROM users WHERE Field='password';" zotprime_www 2>&1 | tail -10
```

- [ ] **Step 4: curl 验证新端点 — listUsers 不含 password**

```bash
TOKEN=$(grep '^API_SUPER_TOKEN=' /home/fz/project/zotprime/.env | cut -d= -f2- | tr -d '"' | tr -d "'")
echo "--- listUsers 响应 keys (应无 'password') ---"
curl -sS -H "Authorization: Bearer $TOKEN" http://localhost:8080/admin/users \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('keys:', list(d[0].keys()) if d else 'empty')"
```

预期:`keys: ['userID', 'username', 'email', 'enabled']` (无 `password`)

- [ ] **Step 5: curl 验证 /api/auth/login 缺 super token → 403**

```bash
echo "--- no super token ---"
curl -sS -w "\nHTTP %{http_code}\n" -X POST http://localhost:8080/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"test","password":"test"}'
```

预期: HTTP 403 + `{"error":"Super user access required"}`

- [ ] **Step 6: curl 验证 /api/auth/login 注册新用户后登录**

```bash
TOKEN=$(grep '^API_SUPER_TOKEN=' /home/fz/project/zotprime/.env | cut -d= -f2- | tr -d '"' | tr -d "'")
USERNAME="bcrypt_$(date +%s)"
EMAIL="${USERNAME}@bcrypt.local"
PASSWD="BcryptPass123!"

echo "--- register via createUser (now bcrypt) ---"
curl -sS -w "\nHTTP %{http_code}\n" -X POST http://localhost:8080/admin/users \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$USERNAME\",\"email\":\"$EMAIL\",\"password\":\"$PASSWD\"}"

echo "--- verify DB has bcrypt hash (not MD5) ---"
mysql -h 127.0.0.1 -P 3306 -u root -p"$(grep '^MARIADB_ROOT_PASSWORD=' /home/fz/project/zotprime/.env | cut -d= -f2- | tr -d '"' | tr -d "'")" -e "SELECT password FROM users WHERE username='$USERNAME';" zotprime_www 2>&1 | tail -3
```

预期:返回 `$2y$10$...` 形式 (bcrypt 60 字符 hash)

- [ ] **Step 7: curl 验证 /api/auth/login 正确密码**

```bash
TOKEN=$(grep '^API_SUPER_TOKEN=' /home/fz/project/zotprime/.env | cut -d= -f2- | tr -d '"' | tr -d "'")
echo "--- correct password ---"
curl -sS -w "\nHTTP %{http_code}\n" -X POST http://localhost:8080/api/auth/login \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWD\"}"
```

预期: HTTP 200 + `{"success":true,"userID":...,"apiKey":"..."}`

- [ ] **Step 8: curl 验证 /api/auth/login 错密码 → 401**

```bash
TOKEN=$(grep '^API_SUPER_TOKEN=' /home/fz/project/zotprime/.env | cut -d= -f2- | tr -d '"' | tr -d "'")
echo "--- wrong password ---"
curl -sS -w "\nHTTP %{http_code}\n" -X POST http://localhost:8080/api/auth/login \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$USERNAME\",\"password\":\"WRONG\"}"
```

预期: HTTP 401 + `{"error":"Invalid credentials"}`

- [ ] **Step 9: 验证 auto-migrate on MD5 user**

(找一个已存在的 user,直接 UPDATE DB 把 password 改为 MD5,然后用对密码登录,验证 password 升级为 bcrypt)

```bash
TOKEN=$(grep '^API_SUPER_TOKEN=' /home/fz/project/zotprime/.env | cut -d= -f2- | tr -d '"' | tr -d "'")
USERNAME="bcrypt_$(date +%s)"
EMAIL="${USERNAME}@migrate.local"
PASSWD="MigratePass456!"

# Register with new (bcrypt) password
curl -sS -o /dev/null -X POST http://localhost:8080/admin/users \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$USERNAME\",\"email\":\"$EMAIL\",\"password\":\"$PASSWD\"}"

# Downgrade to MD5 in DB (simulate legacy user)
mysql -h 127.0.0.1 -P 3306 -u root -p"$(grep '^MARIADB_ROOT_PASSWORD=' /home/fz/project/zotprime/.env | cut -d= -f2- | tr -d '"' | tr -d "'")" -e "UPDATE users SET password = MD5('$PASSWD') WHERE username = '$USERNAME';" zotprime_www 2>&1 | tail -1

# Confirm it's MD5 (32 hex)
mysql -h 127.0.0.1 -P 3306 -u root -p"$(grep '^MARIADB_ROOT_PASSWORD=' /home/fz/project/zotprime/.env | cut -d= -f2- | tr -d '"' | tr -d "'")" -e "SELECT password FROM users WHERE username='$USERNAME';" zotprime_www 2>&1 | tail -1

# Login with correct password
echo "--- login (should auto-migrate) ---"
curl -sS -w "\nHTTP %{http_code}\n" -X POST http://localhost:8080/api/auth/login \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWD\"}"

# Verify DB now has bcrypt
echo "--- after login DB (should be bcrypt) ---"
mysql -h 127.0.0.1 -P 3306 -u root -p"$(grep '^MARIADB_ROOT_PASSWORD=' /home/fz/project/zotprime/.env | cut -d= -f2- | tr -d '"' | tr -d "'")" -e "SELECT password FROM users WHERE username='$USERNAME';" zotprime_www 2>&1 | tail -1
```

预期: 登录后 DB 中 password 从 32 hex (MD5) 升级为 `$2y$10$...` (bcrypt)

- [ ] **Step 10: commit (no source change, just verification notes)**

无 commit。

## Task 6: portal login/route.ts 重写

**Files:**
- Modify: `stack/webui/portal/app/api/auth/login/route.ts` (完整重写)

- [ ] **Step 1: 完整覆盖原文件**

完整新文件内容:

```typescript
import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/session';
import { getConfig } from '@/lib/config';

export async function POST(request: NextRequest) {
  try {
    const { username, password } = await request.json();

    const config = getConfig();
    
    // Call dataserver's dedicated auth endpoint
    const response = await fetch(`${config.dataserver.url}/api/auth/login`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.dataserver.api_super_token}`,
      },
      body: JSON.stringify({ username, password }),
    });

    if (response.status === 401) {
      return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 });
    }
    if (response.status === 403) {
      return NextResponse.json({ error: 'Authentication service denied access' }, { status: 500 });
    }
    if (response.status === 400) {
      const err = await response.json();
      return NextResponse.json({ error: err.error || 'Bad request' }, { status: 400 });
    }
    if (!response.ok) {
      return NextResponse.json({ error: 'Login failed' }, { status: 500 });
    }

    const result = await response.json();
    
    if (!result.success || !result.userID || !result.apiKey) {
      return NextResponse.json({ error: 'Login failed' }, { status: 500 });
    }

    const session = await getSession();
    session.userId = result.userID;
    session.username = username;
    // Note: we don't have email from the auth endpoint; fetch from admin list if needed.
    // For now leave email empty; it can be filled by a subsequent /admin/users lookup if needed.
    session.email = '';
    session.apiKey = result.apiKey;
    await session.save();

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error('Login error:', error);
    return NextResponse.json({ error: 'Login failed' }, { status: 500 });
  }
}
```

注意:
- 删除全部 `crypto.createHash('md5')` 逻辑
- 删除 `users.find()` 全表扫描
- 删除 `getUserKeys(userId)` 调用(apiKey 已经在响应中)
- session.email 暂时空字符串(后续可加 email lookup;但 PR scope 控制下保持)

- [ ] **Step 2: TS check**

```bash
cd /home/fz/project/zotprime/stack/webui/portal
npx tsc --noEmit 2>&1 | tail -10
```

预期: 无错误 (或仅 environment errors 比如 node_modules 缺失)

- [ ] **Step 3: commit**

```bash
cd /home/fz/project/zotprime
git add stack/webui/portal/app/api/auth/login/route.ts
git commit -m "feat(portal): login uses new /api/auth/login endpoint

- 移除 crypto.createHash('md5') 全部逻辑
- 移除 users.find() 全表扫描
- 移除 getUserKeys 二次调用 (apiKey 现在由 endpoint 一次返回)
- dataserver 服务端处理 password_verify + MD5 auto-migrate

Refs: docs/superpowers/specs/2026-07-05-dataserver-bcrypt-auth-design.md"
```

## Task 7: portal 镜像重建 + 端到端验证

**Files:** 不修改源文件,仅运行

- [ ] **Step 1: 重建 portal 镜像**

```bash
cd /home/fz/project/zotprime/stack
DOCKER_BUILDKIT=1 docker build \
  -f webui/webui.Dockerfile \
  -t uniuu/zotprime-portal:v3.2.0 \
  -t uniuu/zotprime-portal:v0.3.0 \
  webui/ 2>&1 | tail -5
```

- [ ] **Step 2: 重启 portal 容器**

```bash
cd /home/fz/project/zotprime
docker compose --profile portal up -d --force-recreate zotprime-portal 2>&1 | tail -3
sleep 5
```

- [ ] **Step 3: 端到端 curl 验证**

```bash
COOKIE=/tmp/portal-bcrypt-cookie.txt
rm -f "$COOKIE"
USERNAME="e2e_bcrypt_$(date +%s)"
EMAIL="${USERNAME}@bcrypt.local"
PASSWD="BcryptE2EPass789!"

echo "--- register ---"
curl -sS -c "$COOKIE" -w "\nHTTP %{http_code}\n" -X POST http://localhost:3045/api/auth/register \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$USERNAME\",\"email\":\"$EMAIL\",\"password\":\"$PASSWD\"}"

echo "--- login ---"
rm -f "$COOKIE"
curl -sS -c "$COOKIE" -w "\nHTTP %{http_code}\n" -X POST http://localhost:3045/api/auth/login \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWD\"}"

echo "--- wrong password ---"
curl -sS -w "\nHTTP %{http_code}\n" -X POST http://localhost:3045/api/auth/login \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$USERNAME\",\"password\":\"WRONG\"}"

echo "--- /portal with cookie ---"
curl -sS -b "$COOKIE" -o /dev/null -w "HTTP %{http_code}\n" http://localhost:3045/portal
```

预期:
- register → 200 `{"success":true}`
- login → 200 `{"success":true}`
- wrong password → 401 `{"error":"Invalid credentials"}`
- /portal with cookie → 200

## Task 8: e2e 测试追加 4 个 step

**Files:**
- Modify: `stack/webui/portal/tests/e2e/portal.spec.ts` (追加 4 step)

- [ ] **Step 1: 在现有 test 块之后追加 4 个 test()**

(F-4 引入的 7 步测试已有,在 `test.describe('Portal intranet flow', () => { ... })` 块的 closing `});` 之前插入)

4 个新 test 应当:

**Test 8 — auto-migrate 旧 MD5 user:**
- 用一个 super token curl 调用 `/admin/users` 创建 fresh user(用 BCrypt)
- 降级 DB: `UPDATE users SET password = MD5('migratepass') WHERE username = 'e2e_migrate_<ts>' LIMIT 1`
- POST `/api/auth/login` with 对密码 → 期望 200
- 验证 DB 中 password 现在是 `$2y$10$...`

**Test 9 — 错密码 401:**
- 已有 register 流程得到一个 user
- POST `/api/auth/login` with 错密码 → 期望 401
- 验证 body 含 "Invalid credentials"

**Test 10 — 缺 super token (直接 hit dataserver):**
- 不带 Authorization header 直接 POST `http://localhost:8080/api/auth/login`
- 期望 403 `{"error":"Super user access required"}`

**Test 11 — listUsers 不返回 password:**
- super token GET `http://localhost:8080/admin/users`
- 验证第一个 user 的 keys 不含 'password'

测试代码 subagent 应当按 F-4 已建立的 7 步测试的命名约定/模式编写。

- [ ] **Step 2: 跑 e2e 11/11**

```bash
cd /home/fz/project/zotprime/stack/webui/portal
PORTAL_BASE_URL=http://localhost:3045 npm run e2e 2>&1 | tail -20
```

预期: 11 passed

- [ ] **Step 3: commit**

```bash
cd /home/fz/project/zotprime
git add stack/webui/portal/tests/e2e/portal.spec.ts
git commit -m "test(portal): add 4 e2e steps for bcrypt + auto-migrate + 401/403

- step 8: 旧 MD5 用户登录后自动升级为 bcrypt
- step 9: 错密码 401 + Invalid credentials
- step 10: 缺 super token 403 + Super user access required
- step 11: listUsers 不返回 password 字段

F-4 的 7 步保留,现在 11/11 e2e PASS."
```

## Task 9: 文档更新 + 推送

**Files:**
- Modify: `docs/notes/2026-07-05-portal-no-2fa-followups.md`

- [ ] **Step 1: 更新 F-1 + F-3 段为 [DONE]**

按 F-2/F-5/F-6 已有 [DONE] 段的格式,把 F-1 和 F-3 段从 [HIGH] / [MEDIUM] 改为 [DONE 2026-07-05] 并附 commit SHA + 实施细节。

- [ ] **Step 2: commit + push**

```bash
cd /home/fz/project/zotprime
git add docs/notes/2026-07-05-portal-no-2fa-followups.md
git commit -m "docs(notes): mark F-1 + F-3 as DONE (bcrypt + auth endpoint)"
git push origin feat/dataserver-bcrypt-auth
```

## Task 10: merge 到 docs/restructure

**Files:** git 操作

- [ ] **Step 1: 切到 docs/restructure,stash pre-existing 改动,merge feature 分支**

```bash
cd /home/fz/project/zotprime
git stash push -u -m "pre-merge-bcrypt: save working tree" 2>&1
git switch docs/restructure 2>&1
git merge --no-ff feat/dataserver-bcrypt-auth -m "Merge branch 'feat/dataserver-bcrypt-auth' into docs/restructure

F-1 + F-3 实施: dataserver bcrypt 迁移 + 专用 /api/auth/login endpoint

- createUser: MD5(?) -> password_hash(?, PASSWORD_BCRYPT)
- listUsers: 移除 password 字段返回
- 新增 authLoginAction (public) + authenticate (private)
  - password_verify() 失败 -> 32hex MD5 fallback -> auto-upgrade
- routes.inc.php: 新增 /api/auth/login 路由
- db_update.sh: ALTER TABLE users MODIFY password varchar(60)
- www.sql: 同步全新部署 schema
- portal login/route.ts: 删 MD5 + users.find 全部逻辑, 改调新端点
- e2e: 11/11 通过 (F-4 的 7 步 + 4 个新 step)

Refs:
  - docs/superpowers/specs/2026-07-05-dataserver-bcrypt-auth-design.md
  - docs/notes/2026-07-05-portal-no-2fa-followups.md" 2>&1 | tail -5
```

- [ ] **Step 2: push + cleanup**

```bash
git push origin docs/restructure 2>&1 | tail -3
git push origin --delete feat/dataserver-bcrypt-auth 2>&1 | tail -2
git branch -d feat/dataserver-bcrypt-auth 2>&1 | tail -2
```

- [ ] **Step 3: pop stash 恢复 working tree**

```bash
git stash pop 2>&1 | tail -5
git status --short
```

预期: 2 modified + 5 untracked (与本会话开始一致)

## 总结

完成 Task 1-10 后交付:
- 干净的 bcrypt 迁移(老用户无感升级,新用户直接存 bcrypt)
- 替代 portal 端 MD5 hash + 全表扫描的专用 auth endpoint
- 11 步 e2e 自动化测试覆盖 happy path + auto-migrate + 错误路径
- PR ready for review

后续 F-4 的 rate limiting gap 在 F-7 单独处理(本 PR 范围之外)。
