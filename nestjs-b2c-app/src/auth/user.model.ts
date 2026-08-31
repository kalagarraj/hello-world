import type { IdTokenClaims } from 'openid-client';

/**
 * The shape we keep in the session. Azure AD B2C returns e-mail addresses in an
 * `emails` array rather than the standard `email` claim, and the object id of
 * the local B2C account in `oid`, so both are normalised here.
 */
export interface AppUser {
  id: string;
  name: string;
  email?: string;
  givenName?: string;
  familyName?: string;
  identityProvider?: string;
  policy?: string;
  issuedAt?: number;
  expiresAt?: number;
  claims: Record<string, unknown>;
  idToken?: string;
  /**
   * Kept so the app can call a downstream API on the user's behalf. B2C only
   * returns one addressed to another API when that API's scope was requested,
   * so this can be absent even on a successful sign-in.
   */
  accessToken?: string;
}

interface B2cClaims extends IdTokenClaims {
  emails?: string[];
  given_name?: string;
  family_name?: string;
  idp?: string;
  tfp?: string;
}

export function toAppUser(
  claims: IdTokenClaims,
  idToken?: string,
  accessToken?: string,
): AppUser {
  const b2c = claims as B2cClaims;
  const email =
    (Array.isArray(b2c.emails) ? b2c.emails[0] : undefined) ??
    (typeof b2c.email === 'string' ? b2c.email : undefined);

  const fullName = [b2c.given_name, b2c.family_name].filter(Boolean).join(' ');

  return {
    id: (b2c.oid as string | undefined) ?? b2c.sub,
    name: (b2c.name as string | undefined) || fullName || email || b2c.sub,
    email,
    givenName: b2c.given_name,
    familyName: b2c.family_name,
    identityProvider: b2c.idp ?? 'Local B2C account',
    policy: b2c.tfp ?? (b2c.acr as string | undefined),
    issuedAt: b2c.iat,
    expiresAt: b2c.exp,
    claims: { ...(b2c as Record<string, unknown>) },
    idToken,
    accessToken,
  };
}
