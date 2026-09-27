import { OAuth2Client } from 'google-auth-library';
import { env } from '../../config/env.js';
import { UnauthorizedError, ValidationError } from './errors.js';

export interface VerifiedGoogleProfile {
  sub: string;
  email: string;
  name: string;
  emailVerified: boolean;
}

let oauthClient: OAuth2Client | null = null;

function getClient(): OAuth2Client {
  if (!oauthClient) oauthClient = new OAuth2Client();
  return oauthClient;
}

/**
 * Verify a Google ID token server-side (P0). Accepts identity claims ONLY
 * after signature + issuer + audience + expiry verification.
 * Throws when GOOGLE_CLIENT_ID is not configured or the token is invalid.
 */
export async function verifyGoogleIdToken(idToken: string): Promise<VerifiedGoogleProfile> {
  if (!idToken || typeof idToken !== 'string') {
    throw new ValidationError('Google ID token is required');
  }
  const audiences = [env.GOOGLE_CLIENT_ID, ...(env.GOOGLE_CLIENT_IDS ? env.GOOGLE_CLIENT_IDS.split(',').map((s) => s.trim()).filter(Boolean) : [])].filter(
    Boolean
  ) as string[];
  if (audiences.length === 0) {
    throw new UnauthorizedError('Google Sign-In is not configured on the server');
  }
  try {
    const ticket = await getClient().verifyIdToken({ idToken, audience: audiences });
    const payload = ticket.getPayload();
    if (!payload || !payload.sub || !payload.email) {
      throw new UnauthorizedError('Invalid Google identity token');
    }
    return {
      sub: payload.sub,
      email: payload.email,
      name: payload.name || payload.email,
      emailVerified: payload.email_verified === true,
    };
  } catch (err: any) {
    if (err && (err.code === 'AUTH_FAILED' || err.statusCode)) throw err;
    throw new UnauthorizedError('Google identity verification failed');
  }
}

/** Only these roles may ever result from client-facing auth. Never admin. */
export function normalizeAuthRole(role: unknown, fallback: 'user' | 'partner' = 'user'): 'user' | 'partner' {
  if (role === 'partner') return 'partner';
  if (role === 'user') return 'user';
  return fallback;
}
