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