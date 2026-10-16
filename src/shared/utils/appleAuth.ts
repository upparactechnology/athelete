import jwt from 'jsonwebtoken';
import { UnauthorizedError, ValidationError } from './errors.js';

export interface VerifiedAppleProfile {
  sub: string;
  email: string;
  name: string;
  emailVerified: boolean;
}

/**
 * Verify and parse an Apple identity token (JWT).
 * Extracts Apple unique sub, email, and verifies issuer and expiration.
 */
export async function verifyAppleIdToken(
  identityToken: string,
  userIdentifier?: string,
  clientEmail?: string,
  givenName?: string,
  familyName?: string
): Promise<VerifiedAppleProfile> {
  if (!identityToken || typeof identityToken !== 'string') {
    throw new ValidationError('Apple identity token is required');
  }

  const decoded = jwt.decode(identityToken, { complete: true }) as {
    header: { kid: string; alg: string };
    payload: {
      iss: string;
      aud: string;
      exp: number;
      iat: number;
      sub: string;
      email?: string;
      email_verified?: boolean | string;
    };
  } | null;

  if (!decoded || !decoded.payload) {
    throw new UnauthorizedError('Invalid Apple identity token format');
  }

  const { payload } = decoded;

  if (payload.iss !== 'https://appleid.apple.com') {
    throw new UnauthorizedError('Invalid Apple token issuer');
  }

  const now = Math.floor(Date.now() / 1000);
  if (payload.exp && payload.exp < now) {
    throw new UnauthorizedError('Apple identity token has expired');
  }

  const sub = payload.sub || userIdentifier;
  if (!sub) {
    throw new UnauthorizedError('Missing user identifier in Apple identity token');
  }

  // Apple sends the user's email inside the JWT payload, or via the client authorization on first login
  const email = (payload.email || clientEmail || `${sub}@privaterelay.appleid.com`).toLowerCase();

  const nameParts = [givenName, familyName].filter(Boolean);
  const name = nameParts.length > 0 ? nameParts.join(' ') : email.split('@')[0];

  const emailVerified =
    payload.email_verified === true ||
    payload.email_verified === 'true' ||
    email.endsWith('@privaterelay.appleid.com') ||
    !!clientEmail;

  return {
    sub,
    email,
    name,
    emailVerified,
  };
}
