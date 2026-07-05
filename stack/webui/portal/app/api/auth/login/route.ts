import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/session';
import { getConfig } from '@/lib/config';

export async function POST(request: NextRequest) {
  try {
    const { username, password } = await request.json();

    const config = getConfig();

    // Call dataserver's dedicated auth endpoint.
    // Dataserver handles password_verify + MD5-to-bcrypt auto-migrate.
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
    if (response.status === 400) {
      const err = await response.json().catch(() => ({}));
      return NextResponse.json(
        { error: err.error || 'Bad request' },
        { status: 400 }
      );
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
    // Email is not exposed by the auth endpoint; consumers that need it
    // can fetch it via a subsequent admin call (out of scope here).
    session.email = '';
    session.apiKey = result.apiKey;
    await session.save();

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error('Login error:', error);
    return NextResponse.json({ error: 'Login failed' }, { status: 500 });
  }
}
