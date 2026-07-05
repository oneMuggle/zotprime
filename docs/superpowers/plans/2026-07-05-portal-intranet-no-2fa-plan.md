# Portal 内网部署 + 移除二维码 2FA 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修改 ZotPrime Portal（`stack/webui/portal/`，Next.js 16 + iron-session）移除二维码 TOTP 强制二因素验证，使其可在内网环境以单一用户名/密码登录部署。

**Architecture:** 一次彻底的代码精简：删除 TOTP 数据层（`lib/totp.ts`、`lib/db.ts`、`totpSecret` 字段），移除 `/verify` 页面与路由，注册 + 登录成功后直接进入 `/portal`。容器层（`docker-compose.yml`）已具备内网部署能力，本次不动。

**Tech Stack:** Next.js 16.1 · React 19.2 · iron-session 8.0.4 · TypeScript 5 · ESLint 9 · Docker Compose

## Global Constraints

- **范围严格限制**：不动 `stack/admin/`、`stack/dataserver/`、`stack/webui/admin/`，不动 `docker-compose.yml`。
- **保留**：未引用的 `bcrypt` / `@types/nodemailer` / `@types/bcrypt` 不动（避免扩大 PR 范围）。
- **内网环境**：`SECURE_COOKIES=false`（HTTP），`.env` 中已由 `bin/deploy-intranet.sh` 注入。
- **不会引入** 单测框架、Playwright、E2E 测试代码。
- **Cookie 兼容性**：`iron-session` 8.x 默认宽容忽略未声明字段，旧 cookie 中的 `totpSecret`/`totpVerified` 会被静默丢弃，无需运行时迁移代码。
- **验证标准**：每个 task 的可验证交付物是"`npm run build` 退出码 0"或"指定文件存在/不存在"。
- **commit 规范**：conventional commit 格式，仅 feat / docs / chore / build / ci 类型。
- **分支命名**：`feat/portal-intranet-no-2fa`，基于 `docs/restructure` 父提交 `e12ca9f1` 之上（**注意**：当前 working tree 还有未提交的其它改动，本实施在新分支上做，不影响那些改动）。

---

## 文件结构

**删除：**
- `stack/webui/portal/lib/totp.ts`
- `stack/webui/portal/lib/db.ts`
- `stack/webui/portal/app/verify/page.tsx`
- `stack/webui/portal/app/api/auth/verify/route.ts`

**清理空目录：**
- `stack/webui/portal/app/verify/`
- `stack/webui/portal/app/api/auth/verify/`
- `stack/webui/portal/data/`（含 `db.json`）

**修改：**
- `stack/webui/portal/types/index.ts` — `SessionData` 删除两个 TOTP 字段
- `stack/webui/portal/package.json` — 移除三个 dependencies + 一个 devDependency
- `stack/webui/portal/app/api/auth/login/route.ts` — 去除 TOTP 引用 + 直接 `apiKey` 入 session
- `stack/webui/portal/app/api/auth/register/route.ts` — 去除 TOTP 生成 + 直接 `apiKey` 入 session
- `stack/webui/portal/app/login/page.tsx` — 登录成功 `push('/portal')`（不再 `/verify`）
- `stack/webui/portal/app/register/page.tsx` — 注册成功 `push('/portal')`（不再 `/verify`）

**新增：**
- `docs/user-manual/50-portal-intranet.md`

---

## Task 1: 建 feature 分支

**Files:**
- 不修改文件，仅 git 操作

**Interfaces:**
- 当前父提交：`e12ca9f1 docs(spec): draft portal intranet deployment + remove 2FA design`
- 当前分支：`docs/restructure`（有未提交改动，不污染）

- [ ] **Step 1: 确认 git 状态干净（除已知未提交改动外）**

```bash
cd /home/fz/project/zotprime
git status --short
```

预期：输出与开始时一致（`M bin/deploy-intranet.sh`、`M docker-compose.yml`、`M docs/user-manual/README.md` + 若干 untracked 文件）。这些改动不会污染新分支。

- [ ] **Step 2: 基于 docs/restructure 创建并切换 feature 分支**

```bash
git switch -c feat/portal-intranet-no-2fa
```

预期：`Switched to a new branch 'feat/portal-intranet-no-2fa'`

- [ ] **Step 3: 验证新分支包含 spec 文档**

```bash
ls docs/superpowers/specs/2026-07-05-portal-intranet-no-2fa-design.md
```

预期：文件存在。无需再 commit spec（已随父分支继承）。

---

## Task 2: 清理数据层 — 删 TOTP/DB 文件 + 类型收缩

**Files:**
- Delete: `stack/webui/portal/lib/totp.ts`
- Delete: `stack/webui/portal/lib/db.ts`
- Modify: `stack/webui/portal/types/index.ts` — `SessionData` 移除 `totpSecret?` 与 `totpVerified?`

**Interfaces:**
- `SessionData` 是 `iron-session` 在 `lib/session.ts` 与登录/注册路由共用的 cookie 反序列化 schema

- [ ] **Step 1: 删除两个 lib 文件**

```bash
cd /home/fz/project/zotprime
git rm stack/webui/portal/lib/totp.ts stack/webui/portal/lib/db.ts
```

预期：两文件 staged for deletion。

- [ ] **Step 2: 修改 `stack/webui/portal/types/index.ts` — 移除 SessionData 的 TOTP 字段**

完整覆盖原文件为以下内容：

```typescript
export interface User {
  userID: number;
  username: string;
  email: string;
}

export interface SessionData {
  userId: number;
  username: string;
  email: string;
  apiKey: string;
}

export interface ZoteroGroup {
  id: number;
  version: number;
  data: {
    id: number;
    version: number;
    name: string;
    description?: string;
    type: string;
    owner: number;
  };
}

export interface ZoteroItem {
  key: string;
  version: number;
  library: {
    type: string;
    id: number;
    name: string;
  };
  data: {
    key: string;
    version: number;
    itemType: string;
    title?: string;
    creators?: Array<{
      creatorType: string;
      firstName?: string;
      lastName?: string;
      name?: string;
    }>;
    abstractNote?: string;
    date?: string;
    url?: string;
    tags?: Array<{ tag: string }>;
    [key: string]: any;
  };
}

export interface RegistrationData {
  username: string;
  email: string;
  password: string;
  honeypot?: string;
  captchaToken: string;
}

export interface LoginData {
  username: string;
  password: string;
  captchaToken: string;
}
```

- [ ] **Step 3: 检查 TS 编译（本 task 只动了数据层 + 类型）**

```bash
cd /home/fz/project/zotprime/stack/webui/portal
npx tsc --noEmit 2>&1 | tee /tmp/tsc-task2.log
```

预期：可能因下游路由还在 import `totp`/`db` 而报"cannot find module '@/lib/totp'"或"property totpSecret does not exist on SessionData"——**这是预期的**，由后续 task 解决。**不要因报错而回退。**

下游路由消费（待清理）：
- `app/api/auth/login/route.ts` import `getTOTPSecret`, `generateTOTPUri`, `generateQRCode`
- `app/api/auth/register/route.ts` import `generateTOTPSecret`, `generateTOTPUri`, `generateQRCode`, `setTOTPSecret`
- `app/api/auth/verify/route.ts` import `verifyTOTP`, `markTOTPVerified`

- [ ] **Step 4: git add + commit**

```bash
cd /home/fz/project/zotprime
git add stack/webui/portal/lib/totp.ts stack/webui/portal/lib/db.ts stack/webui/portal/types/index.ts
git commit -m "refactor(portal): remove TOTP data layer

- Delete lib/totp.ts (otpauth + qrcode wrapper)
- Delete lib/db.ts (lowdb totpSecrets store)
- Shrink SessionData: drop totpSecret? and totpVerified?

后续任务将清理引用此模块的路由与页面。

Refs: docs/superpowers/specs/2026-07-05-portal-intranet-no-2fa-design.md"
```

预期：1 commit created, 2 files deleted, 1 file modified.

---

## Task 3: 修改 login route + login 页面（无 TOTP,登录即跳 portal）

**Files:**
- Modify: `stack/webui/portal/app/api/auth/login/route.ts` — 完整重写
- Modify: `stack/webui/portal/app/login/page.tsx` — 登录成功 push `/portal`

**Interfaces:**
- `LoginData` (`types/index.ts`) — `{ username, password, captchaToken }`
- `getSession()` 返回 `IronSession<SessionData>`
- `getUserKeys(userId)` 返回 `string | null`

- [ ] **Step 1: 重写 login route**

完整覆盖 `stack/webui/portal/app/api/auth/login/route.ts`：

```typescript
import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/session';
import { getConfig } from '@/lib/config';
import { getUserKeys } from '@/lib/api';

export async function POST(request: NextRequest) {
  try {
    const { username, password } = await request.json();

    const config = getConfig();
    const response = await fetch(`${config.dataserver.url}/admin/users`, {
      headers: {
        'Authorization': `Bearer ${config.dataserver.api_super_token}`,
      },
    });

    if (!response.ok) {
      return NextResponse.json({ error: 'Login failed' }, { status: 401 });
    }

    const users = await response.json();
    const user = users.find((u: any) => u.username === username);

    if (!user) {
      return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 });
    }

    // Verify password (dataserver stores MD5 hashes)
    const crypto = require('crypto');
    const passwordHash = crypto.createHash('md5').update(password).digest('hex');

    if (user.password !== passwordHash) {
      return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 });
    }

    // Fetch API key for user (replaces previous TOTP step)
    const apiKey = await getUserKeys(user.userID);
    if (!apiKey) {
      return NextResponse.json({ error: 'No API key found' }, { status: 500 });
    }

    const session = await getSession();
    session.userId = user.userID;
    session.username = user.username;
    session.email = user.email;
    session.apiKey = apiKey;
    await session.save();

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error('Login error:', error);
    return NextResponse.json({ error: 'Login failed' }, { status: 500 });
  }
}
```

- [ ] **Step 2: 重写 login 页面**

完整覆盖 `stack/webui/portal/app/login/page.tsx`：

```typescript
'use client';

import { useState } from 'react';
import { useForm } from 'react-hook-form';
import Link from 'next/link';
import { useRouter } from 'next/navigation';

type LoginFormData = {
  username: string;
  password: string;
};

export default function LoginPage() {
  const router = useRouter();
  const { register, handleSubmit, formState: { errors } } = useForm<LoginFormData>();
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const onSubmit = handleSubmit(async (data) => {
    setLoading(true);
    setError('');

    try {
      const response = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });

      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.error || 'Login failed');
      }

      router.push('/portal');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed');
    } finally {
      setLoading(false);
    }
  });

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div className="max-w-md w-full bg-white rounded-lg shadow p-8">
        <h1 className="text-2xl font-bold mb-6 text-gray-900">Login</h1>

        {error && (
          <div className="bg-red-50 text-red-600 p-3 rounded mb-4">
            {error}
          </div>
        )}

        <form onSubmit={onSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium mb-1 text-gray-900">Username</label>
            <input
              {...register('username', { required: 'Username is required' })}
              className="w-full border rounded px-3 py-2 text-gray-900"
            />
            {errors.username && (
              <p className="text-red-600 text-sm mt-1">{errors.username.message}</p>
            )}
          </div>

          <div>
            <label className="block text-sm font-medium mb-1 text-gray-900">Password</label>
            <input
              type="password"
              {...register('password', { required: 'Password is required' })}
              className="w-full border rounded px-3 py-2 text-gray-900"
            />
            {errors.password && (
              <p className="text-red-600 text-sm mt-1">{errors.password.message}</p>
            )}
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full bg-blue-600 text-white py-2 rounded hover:bg-blue-700 disabled:opacity-50"
          >
            {loading ? 'Logging in...' : 'Login'}
          </button>
        </form>

        <p className="mt-4 text-center text-sm text-gray-800">
          Don&apos;t have an account?{' '}
          <Link href="/register" className="text-blue-600 hover:underline">
            Register
          </Link>
        </p>
      </div>
    </div>
  );
}
```

- [ ] **Step 3: 检查 TS 编译（本 task 只动了 login 路径）**

```bash
cd /home/fz/project/zotprime/stack/webui/portal
npx tsc --noEmit 2>&1 | tee /tmp/tsc-task3.log
```

预期：本 task 引入的 2 个文件本身应当无误。下游 register route / verify route 仍在 import 已被删的模块——预期会报错，集中于这几个文件中。

- [ ] **Step 4: git add + commit**

```bash
cd /home/fz/project/zotprime
git add stack/webui/portal/app/api/auth/login/route.ts stack/webui/portal/app/login/page.tsx
git commit -m "feat(portal): login without 2FA

登录成功直接进入 /portal。
- login route: 移除 TOTP 检查, 登录后立即设置 apiKey 进 session
- login page: 登录成功 router.push('/portal')(不再 /verify)"
```

预期：1 commit, 2 files modified.

---

## Task 4: 修改 register route + register 页面（注册即跳 portal）

**Files:**
- Modify: `stack/webui/portal/app/api/auth/register/route.ts` — 完整重写
- Modify: `stack/webui/portal/app/register/page.tsx` — 注册成功 push `/portal`

**Interfaces:**
- `createUser(username, email, password)` — 抛错则中止
- `createApiKey(userId, name)` — 返回 `string`
- `getSession()` 返回 `IronSession<SessionData>`

- [ ] **Step 1: 重写 register route**

完整覆盖 `stack/webui/portal/app/api/auth/register/route.ts`：

```typescript
import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/session';
import { createUser, createApiKey } from '@/lib/api';

export async function POST(request: NextRequest) {
  try {
    const { username, email, password } = await request.json();

    // Create user in dataserver (send plain password, dataserver will hash with MD5)
    const user = await createUser(username, email, password);

    // Create API key for user
    const apiKey = await createApiKey(user.userID, 'Portal Access');

    const session = await getSession();
    session.userId = user.userID;
    session.username = username;
    session.email = email;
    session.apiKey = apiKey;
    await session.save();

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error('Registration error:', error);
    return NextResponse.json(
      { error: error instanceof Error ? error.message : 'Registration failed' },
      { status: 500 }
    );
  }
}
```

注意：原文件 import 了 `bcrypt` 和 totp/db 模块，新文件完全不再需要 `bcrypt` import。**保留 package.json 中的 `bcrypt` 不动**（见 spec §1 "保留未引用依赖"）。

- [ ] **Step 2: 重写 register 页面**

完整覆盖 `stack/webui/portal/app/register/page.tsx`：

```typescript
'use client';

import { useState } from 'react';
import { useForm } from 'react-hook-form';
import Link from 'next/link';
import { useRouter } from 'next/navigation';

type RegisterFormData = {
  username: string;
  email: string;
  password: string;
  confirmPassword: string;
  honeypot: string;
};

export default function RegisterPage() {
  const router = useRouter();
  const { register, handleSubmit, formState: { errors }, watch } = useForm<RegisterFormData>();
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const onSubmit = handleSubmit(async (data) => {
    if (data.honeypot) {
      return; // Bot detected
    }

    setLoading(true);
    setError('');

    try {
      const response = await fetch('/api/auth/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          username: data.username,
          email: data.email,
          password: data.password,
        }),
      });

      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.error || 'Registration failed');
      }

      router.push('/portal');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Registration failed');
    } finally {
      setLoading(false);
    }
  });

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div className="max-w-md w-full bg-white rounded-lg shadow p-8">
        <h1 className="text-2xl font-bold mb-6 text-gray-900">Register</h1>

        {error && (
          <div className="bg-red-50 text-red-600 p-3 rounded mb-4">
            {error}
          </div>
        )}

        <form onSubmit={onSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium mb-1 text-gray-900">Username</label>
            <input
              {...register('username', {
                required: 'Username is required',
                minLength: { value: 3, message: 'Minimum 3 characters' },
              })}
              className="w-full border rounded px-3 py-2 text-gray-900"
            />
            {errors.username && (
              <p className="text-red-600 text-sm mt-1">{errors.username.message}</p>
            )}
          </div>

          <div>
            <label className="block text-sm font-medium mb-1 text-gray-900">Email</label>
            <input
              type="email"
              {...register('email', {
                required: 'Email is required',
                pattern: { value: /^\S+@\S+$/i, message: 'Invalid email' },
              })}
              className="w-full border rounded px-3 py-2 text-gray-900"
            />
            {errors.email && (
              <p className="text-red-600 text-sm mt-1">{errors.email.message}</p>
            )}
          </div>

          <div>
            <label className="block text-sm font-medium mb-1 text-gray-900">Password</label>
            <input
              type="password"
              {...register('password', {
                required: 'Password is required',
                minLength: { value: 8, message: 'Minimum 8 characters' },
              })}
              className="w-full border rounded px-3 py-2 text-gray-900"
            />
            {errors.password && (
              <p className="text-red-600 text-sm mt-1">{errors.password.message}</p>
            )}
          </div>

          <div>
            <label className="block text-sm font-medium mb-1 text-gray-900">Confirm Password</label>
            <input
              type="password"
              {...register('confirmPassword', {
                required: 'Please confirm password',
                validate: (val) => val === watch('password') || 'Passwords do not match',
              })}
              className="w-full border rounded px-3 py-2 text-gray-900"
            />
            {errors.confirmPassword && (
              <p className="text-red-600 text-sm mt-1">{errors.confirmPassword.message}</p>
            )}
          </div>

          {/* Honeypot field */}
          <input
            {...register('honeypot')}
            type="text"
            className="hidden"
            tabIndex={-1}
            autoComplete="off"
          />

          <button
            type="submit"
            disabled={loading}
            className="w-full bg-blue-600 text-white py-2 rounded hover:bg-blue-700 disabled:opacity-50"
          >
            {loading ? 'Registering...' : 'Register'}
          </button>
        </form>

        <p className="mt-4 text-center text-sm text-gray-800">
          Already have an account?{' '}
          <Link href="/login" className="text-blue-600 hover:underline">
            Login
          </Link>
        </p>
      </div>
    </div>
  );
}
```

- [ ] **Step 3: 检查 TS 编译（本 task 只动了 register 路径）**

```bash
cd /home/fz/project/zotprime/stack/webui/portal
npx tsc --noEmit 2>&1 | tee /tmp/tsc-task4.log
```

预期：本 task 应当消除 register route / register page 路径上的 TOTP/QR 引用错误。**但**仍未删除的 `app/api/auth/verify/route.ts` 还会引用已删的 `@/lib/totp` 与 `@/lib/db`——这是 Task 5 要解决的。

- [ ] **Step 4: git add + commit**

```bash
cd /home/fz/project/zotprime
git add stack/webui/portal/app/api/auth/register/route.ts stack/webui/portal/app/register/page.tsx
git commit -m "feat(portal): register lands directly on /portal

注册成功后立即跳转到 /portal, 不再经过 verify QR 设置流程。
- register route: 删除 TOTP secret 生成与 setTOTPSecret 调用, apiKey 直接进 session
- register page: 注册成功 router.push('/portal')(不再 /verify)"
```

预期：1 commit, 2 files modified.

---

## Task 5: 删除 verify 页面 + verify route

**Files:**
- Delete: `stack/webui/portal/app/verify/page.tsx`
- Delete: `stack/webui/portal/app/api/auth/verify/route.ts`

- [ ] **Step 1: 删除两个文件**

```bash
cd /home/fz/project/zotprime
git rm stack/webui/portal/app/verify/page.tsx stack/webui/portal/app/api/auth/verify/route.ts
```

预期：两文件 staged for deletion。

- [ ] **Step 2: 全项目搜索 `@/lib/totp` 和 `@/lib/db` 残留引用**

```bash
cd /home/fz/project/zotprime/stack/webui/portal
grep -rn "@/lib/totp\|@/lib/db\|from '@/lib/totp'\|from '@/lib/db'\|from '../lib/totp'\|from '../lib/db'" \
  --include="*.ts" --include="*.tsx" \
  app/ lib/ types/
```

预期：**空输出**。如果有任何匹配，回到对应文件清理 import。

- [ ] **Step 3: TS 编译应当干净**

```bash
cd /home/fz/project/zotprime/stack/webui/portal
npx tsc --noEmit
```

预期：退出码 0，零错误。

- [ ] **Step 4: git add + commit**

```bash
cd /home/fz/project/zotprime
git commit -m "refactor(portal): delete /verify page and route

彻底移除 TOTP 验证页面与 API 入口。配合 Task 2-4 的路由改动,
Portal 验证流程完全清除。下游任务清理空目录与依赖。"
```

预期：1 commit, 2 files deleted.

---

## Task 6: 清理空目录 + package.json + npm install + lint + build

**Files:**
- Delete: `stack/webui/portal/app/verify/` (empty)
- Delete: `stack/webui/portal/app/api/auth/verify/` (empty)
- Delete: `stack/webui/portal/data/db.json` (residual)
- Delete: `stack/webui/portal/data/` (empty after db.json removal)
- Modify: `stack/webui/portal/package.json`

**Interfaces:**
- `package.json` scripts: `dev`, `build`, `start`, `lint` —— 全部不变
- `package.json` dependencies 删除项：`otpauth`, `qrcode`, `lowdb`
- `package.json` devDependencies 删除项：`@types/qrcode`

- [ ] **Step 1: 删除空目录**

```bash
cd /home/fz/project/zotprime/stack/webui/portal
ls app/verify/        # 应只剩空目录或不存在
ls app/api/auth/verify/
ls data/              # 应只剩 db.json 或不存在

rmdir app/verify 2>/dev/null || true
rmdir app/api/auth/verify 2>/dev/null || true
rm -f data/db.json
rmdir data 2>/dev/null || true

ls app/verify/ 2>/dev/null && echo "STILL EXISTS" || echo "removed"
ls app/api/auth/verify/ 2>/dev/null && echo "STILL EXISTS" || echo "removed"
ls data/ 2>/dev/null && echo "STILL EXISTS" || echo "removed"
```

预期：三个目录都打印 "removed"。

- [ ] **Step 2: 修改 `stack/webui/portal/package.json`**

完整覆盖为：

```json
{
  "name": "portal",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "eslint"
  },
  "dependencies": {
    "@types/bcrypt": "^6.0.0",
    "@types/js-yaml": "^4.0.9",
    "@types/nodemailer": "^7.0.9",
    "bcrypt": "^6.0.0",
    "iron-session": "^8.0.4",
    "js-yaml": "^4.1.1",
    "next": "16.1.6",
    "react": "19.2.3",
    "react-dom": "19.2.3",
    "react-hook-form": "^7.71.1"
  },
  "devDependencies": {
    "@tailwindcss/postcss": "^4",
    "@types/node": "^20",
    "@types/react": "^19",
    "@types/react-dom": "^19",
    "eslint": "^9",
    "eslint-config-next": "16.1.6",
    "tailwindcss": "^4",
    "typescript": "^5"
  }
}
```

移除了：
- `dependencies.otpauth`
- `dependencies.qrcode`
- `dependencies.lowdb`
- `devDependencies.@types/qrcode`

保留 `bcrypt` / `@types/bcrypt` / `@types/nodemailer`（项目原状未引用，保持原 PR 范围最小化）。

- [ ] **Step 3: npm install**

```bash
cd /home/fz/project/zotprime/stack/webui/portal
npm install 2>&1 | tail -20
```

预期：warning 数量减少（otpauth/qrcode/lowdb 不再安装），无 ERR!。

- [ ] **Step 4: npm run lint**

```bash
cd /home/fz/project/zotprime/stack/webui/portal
npm run lint 2>&1 | tee /tmp/lint-task6.log
```

预期：退出码 0，无 `error` 关键字（warning 可允许）。如果报"`@/lib/totp`"或"`@/lib/db`"找不到——回退到 Task 5 Step 2 检查残留。

- [ ] **Step 5: npm run build**

```bash
cd /home/fz/project/zotprime/stack/webui/portal
npm run build 2>&1 | tee /tmp/build-task6.log
```

预期：退出码 0，输出包含 `Compiled successfully` 或类似成功信息，且 `/(login|register|portal)` 路由成功生成。

- [ ] **Step 6: 检查 `data/` 目录在 git 状态中**

```bash
cd /home/fz/project/zotprime
git status --short stack/webui/portal/
```

预期：`data/db.json` 显示为 deleted（如果 git 曾追踪它）或 untracked cleanups。如从未被追踪，仅显示空目录 cleanup 信息。

- [ ] **Step 7: git add + commit**

```bash
cd /home/fz/project/zotprime
git add -A stack/webui/portal/

git rm --cached stack/webui/portal/app/verify 2>/dev/null || true
git rm --cached stack/webui/portal/app/api/auth/verify 2>/dev/null || true

git commit -m "build(portal): drop unused deps and empty dirs

- Remove deps: otpauth, qrcode, lowdb
- Remove devDep: @types/qrcode
- Remove empty dirs: app/verify, app/api/auth/verify, data/

npm install + lint + build 全绿。

Ref: docs/superpowers/specs/2026-07-05-portal-intranet-no-2fa-design.md"
```

预期：1 commit created，包含 `package.json` 修改 + 若干目录/文件删除。

---

## Task 7: 端到端验证（docker compose + 浏览器）

**Files:** 不修改源文件；仅运行镜像验证

**验证前提：**
- Task 6 验证：`npm run build` 已退出码 0
- `.env` 中 `PORTAL_SESSION_SECRET` / `API_SUPER_TOKEN` / `SECURE_COOKIES=false` 存在
- `bin/deploy-intranet.sh` 用于快速搭建 dataserver + admin 全栈（可复用）

- [ ] **Step 1: 重建 portal 容器镜像**

```bash
cd /home/fz/project/zotprime
docker compose --profile portal build zotprime-portal 2>&1 | tail -20
```

预期：`Successfully tagged ...:latest` 或类似输出，无 build error。

- [ ] **Step 2: 启动 portal（前提：dataserver 等已运行）**

```bash
cd /home/fz/project/zotprime
docker compose --profile portal up -d zotprime-portal
sleep 3
docker compose --profile portal ps zotprime-portal
```

预期：状态 `Up` / `running`。如 dataserver 未启动，先用 `bin/deploy-intranet.sh` 或 `docker compose up -d zotprime-dataserver` 启动。

- [ ] **Step 3: 健康检查 + 网络可达**

```bash
curl -sI http://localhost:3045/ | head -5
```

预期：`HTTP/1.1 200 OK`，Content-Type 是 `text/html`。如果连接被拒，检查端口映射、容器日志 `docker compose --profile portal logs --tail=50 zotprime-portal`。

- [ ] **Step 4: 验证 `/login` 可访问 + 没有 `/verify`**

```bash
curl -sI http://localhost:3045/login | head -3
curl -sI http://localhost:3045/verify | head -3
```

预期：
- `/login` → 200
- `/verify` → 404（next.js 默认行为，删除页面后路由不存在）

- [ ] **Step 5: 浏览器手工测试（参照 spec §8.2 表格）**

打开 `http://localhost:3045/`，执行：

| 步骤 | 预期 |
|---|---|
| 访问 `/` | 显示首页 "Get Started / Sign In" 链接 |
| 点 Sign In → `/login` | 显示二字段表单（username + password），无 /verify 按钮 |
| 注册一个新账号 | 注册成功后 URL 直接变成 `/portal`，不在 `/verify` 中转 |
| 退出登录 → `/` | "Logout" 链接工作，回到首页 |
| 用刚才的账号登录 | 成功进入 `/portal` |
| 清除 cookie 后访问 `/portal` | 自动重定向到 `/login` |
| 5 次错误密码 | 触发 rate limiting（HTTP 429 或 retry-after） |

手工记录每一步的实际结果到 `/tmp/portal-e2e.log`：

```bash
cat > /tmp/portal-e2e.log <<EOF
Test environment: $(date)
Docker image: $(docker images | grep zotprime-portal | head -1)
EOF
# 人工逐项 OK / FAIL 填写到该文件
```

预期：每行测试打 OK。FAIL 时回到 Task 5/6 修复后回到本 Task 重测。

- [ ] **Step 6: commit 检查记录（可选）**

```bash
cd /home/fz/project/zotprime
git add docs/superpowers/specs/ 2>/dev/null  # 如果有更新的验证记录文件
git commit -m "docs(portal): record end-to-end verification log" 2>/dev/null || true
```

预期：可选，无强制要求。

---

## Task 8: 用户手册新增章节

**Files:**
- Create: `docs/user-manual/50-portal-intranet.md`

**Interfaces:**
- 项目现有 user-manual 采用"README.md + 分章节"结构（`docs/user-manual/README.md` 总览）
- 章节命名风格：`数字-短横线-topic.md`，本章节为 `50-portal-intranet.md`

- [ ] **Step 1: 检查现有 user-manual 目录**

```bash
ls /home/fz/project/zotprime/docs/user-manual/
head -30 /home/fz/project/zotprime/docs/user-manual/README.md
```

预期：能看到现有章节列表与编号风格。

- [ ] **Step 2: 创建 `docs/user-manual/50-portal-intranet.md`**

写入完整内容：

````markdown
# Portal 内网部署

ZotPrime Portal 是基于 Next.js 的网页门户，部署在内网环境，监听 `http://SERVER_IP:3045/`。本章节描述其部署、访问流程与运维要点。

## 访问方式

浏览器访问：

```
http://<SERVER_IP>:3045/
```

内网仅需 HTTP，无需 HTTPS（由反向代理或客户端到服务器的可信网络保证）。

## 环境变量

`.env` 中至少包含以下三项：

```bash
PORTAL_SESSION_SECRET=<至少 32 字符的随机字符串>   # iron-session 加密密钥
API_SUPER_TOKEN=<与 dataserver 的 API_SUPER_TOKEN 一致>
SECURE_COOKIES=false                                  # HTTP 内网必须
```

`SECURE_COOKIES=false` 是关键：默认值为 `true`，会让 iron-session 在 HTTP 环境下不下发 cookie，导致登录永远失败。

## 启动

Portal service 在 `docker-compose.yml` 中位于 `profiles: ["portal"]` 分组，需要显式指定：

```bash
docker compose --profile portal up -d zotprime-portal
docker compose --profile portal ps zotprime-portal
```

## 登录流程（无 2FA）

Portal 当前已移除二维码 Authenticator 二因素验证。

- **注册**：访问 `/register`，填写 username / email / password / confirm password → 提交后**直接进入 `/portal`**
- **登录**：访问 `/login`，填写 username / password → 提交后**直接进入 `/portal`**
- **注销**：在 `/portal` 页面右上角点 "Logout" → 回到 `/`

rate limiting 由 `stack/webui/portal/config.yaml` 的 `security.rate_limit` 段控制，5 次/分钟的认证失败将触发限流。

## 旧部署清理

如果升级前的版本曾启用 2FA，容器内可能残留 `stack/webui/portal/data/db.json` 文件：

```bash
# 在 portal 容器内,或在宿主机 (如果 data/ 挂载) 删除:
rm -f /app/data/db.json
```

新版 Portal 不再读写该文件，删除只是回收磁盘。**不影响已经注册的用户**——用户记录在 dataserver 里，与 Portal 无关。

## 故障排查

| 现象 | 原因 | 处置 |
|---|---|---|
| 登录后立刻被踢回登录页 | `SECURE_COOKIES=true` 在 HTTP 下不发 cookie | `.env` 改为 `SECURE_COOKIES=false` + 重启 |
| 登录成功却空白页 | dataserver 未启动 / API token 不一致 | `docker compose logs zotprime-dataserver` |
| `/portal/item/:id` 404 | 该 item 不在登录用户可见的 group 中 | 联系管理员调整 group 成员 |
| 注册报 "user already exists" | username 在 dataserver 中已被占用 | 换一个 username |
````

- [ ] **Step 3: 在 `docs/user-manual/README.md` 章节列表中插入新章节链接**

打开 `README.md`，定位章节表格区域，按编号顺序插入新行：

```markdown
| 50 | [Portal 内网部署](50-portal-intranet.md) | 内网环境下 Portal 的部署、登录流程与环境变量。 |
```

行格式：`| <编号> | [<标题>](<文件路径>) | <一句话简介>。 |`

- [ ] **Step 4: 检查 mkdocs.yml（如存在）**

```bash
grep -n "user-manual" /home/fz/project/zotprime/mkdocs.yml 2>/dev/null || echo "no mkdocs user-manual nav"
```

如果有 `nav` 块，按相同风格追加：

```yaml
- user-manual:
    - ... 既有章节 ...
    - 50-portal-intranet.md
```

如果不存在 `mkdocs.yml` 的 nav 区块或不存在 mkdocs.yml，**跳过此步**。

- [ ] **Step 5: git add + commit**

```bash
cd /home/fz/project/zotprime
git add docs/user-manual/50-portal-intranet.md docs/user-manual/README.md mkdocs.yml 2>/dev/null
git commit -m "docs(user-manual): add Portal intranet deployment chapter (50)

覆盖:
- 端口 3045 访问方式
- SECURE_COOKIES=false 内网 HTTP 必需
- 注册/登录流程(无 2FA)
- 旧 db.json 残留清理
- 故障排查表

在 README.md 章节表中追加链接。"
```

预期：1 commit, 2-3 files changed.

---

## Task 9: 推送与开 PR

**Files:** 不修改文件；git remote 操作

**Interfaces:**
- `origin` 远程指向用户 fork 或主仓库（按 git remote -v 推断）
- `gh` CLI 用于创建 PR（项目已有 `.github/workflows/`）

- [ ] **Step 1: 确认本地历史干净**

```bash
cd /home/fz/project/zotprime
git status --short
git log --oneline docs/restructure..feat/portal-intranet-no-2fa
```

预期：工作树只列出 Task 1-8 之外的文件（如 bin/deploy-intranet.sh 等原 working tree 改动，保持原状）。commit log 显示本实施的所有新提交，根于 `e12ca9f1` 或之后的 docs/restructure HEAD。

- [ ] **Step 2: 推送分支到 origin**

```bash
cd /home/fz/project/zotprime
git push -u origin feat/portal-intranet-no-2fa 2>&1 | tail -10
```

预期：远程端出现新分支。如果 origin 拒绝，检查 `git remote -v`。

- [ ] **Step 3: 用 gh CLI 创建 PR**

```bash
cd /home/fz/project/zotprime
gh pr create \
  --base docs/restructure \
  --head feat/portal-intranet-no-2fa \
  --title "feat(portal): remove TOTP 2FA for intranet deployment" \
  --body "$(cat <<'EOF'
## 背景
ZotPrime Portal 当前强制 TOTP 二因素验证，注册时即生成二维码、登录后必须经 /verify 输入 6 位码才能进入 /portal。内网环境下：
- 每台终端需装 Authenticator App，部署/运维负担过重
- 公网场景才需要的 2FA 在可信网络内价值有限

## 改动（基于 docs/superpowers/specs/2026-07-05-portal-intranet-no-2fa-design.md）
- 删除 lib/totp.ts、lib/db.ts
- 删除 app/verify/* 与 verify route
- login / register route 登录/注册后直接入 /portal
- types SessionData 收缩
- package.json 移除 otpauth/qrcode/lowdb/@types/qrcode
- 用户手册新增 docs/user-manual/50-portal-intranet.md
- 无 docker-compose 改动（已具备内网部署能力）

## 测试
- npm run lint / build 全绿
- docker compose --profile portal build 成功
- 端到端：注册 → /portal、登录 → /portal、未登录访问 /portal → /login 重定向、/verify 返回 404

## 风险
详见 spec §9。最显著：旧浏览器 cookie 触发 iron-session 反序列化警告——iron-session 8.x 默认宽容忽略未声明字段，预期不影响；如严格模式升级需补运行时迁移补丁。

🤖 Generated with [Claude Code](https://claude.ai/code)
EOF
)" 2>&1 | tail -15
```

预期：PR URL 输出，类似 `https://github.com/<owner>/zotprime/pull/<N>`。

- [ ] **Step 4: 监控 PR CI（如项目有 GitHub Actions）**

```bash
cd /home/fz/project/zotprime
gh pr checks --watch 2>&1 | head -30
```

预期：CI jobs 全部 PASS，或显示 queue/progress。如有 FAIL，停止并报告用户（按 CICD-workflow §4 失败处理流程）。

---

## 总结

完成 Task 1-9 后交付：
- 一个干净通过 lint/build 的 portal 代码库（无 TOTP / QR / verify 流程）
- 1 个新用户手册章节
- 1 个 PR ready for review
- 端到端验证记录

后续用户/审阅者 merge 后，按 CICD-workflow §3 推断版本号打 tag。
