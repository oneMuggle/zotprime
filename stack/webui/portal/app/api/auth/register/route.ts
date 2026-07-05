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
