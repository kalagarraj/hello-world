import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/**
 * Everything the app needs to talk OpenID Connect to an Azure AD B2C user flow.
 * Built from environment variables so no secrets live in the repository.
 */
export interface OidcConfig {
  discoveryUrl: string;
  clientId: string;
  /**
   * Omitted for app registrations B2C treats as public clients (redirect URI
   * registered under "Mobile and desktop applications", or "Allow public client
   * flows" set to Yes). Such a registration rejects a secret at the token
   * endpoint with AADB2C90084, so the client is configured without one and
   * relies on PKCE alone.
   */
  clientSecret?: string;
  redirectUri: string;
  postLogoutRedirectUri: string;
  scope: string;
}

/**
 * What the app could and could not work out from the environment. Drives the
 * /setup page so it can name the variables that are actually missing.
 */
export interface OidcStatus {
  configured: boolean;
  missing: string[];
  mode: 'confidential' | 'public' | null;
  discoveryUrl?: string;
  redirectUri: string;
  postLogoutRedirectUri: string;
}

export const OIDC_INSPECTION = 'OIDC_INSPECTION';
export const OIDC_STATUS = 'OIDC_STATUS';
export const OIDC_CONFIG = 'OIDC_CONFIG';
export const OIDC_CLIENT = 'OIDC_CLIENT';
export const OIDC_STRATEGY = 'OIDC_STRATEGY';

/**
 * Azure AD B2C publishes one discovery document per user flow (policy):
 *   https://<tenant>.b2clogin.com/<tenant>.onmicrosoft.com/<policy>/v2.0/.well-known/openid-configuration
 *
 * Set B2C_DISCOVERY_URL directly when using a custom domain or a CIAM
 * (*.ciamlogin.com) tenant, otherwise it is derived from tenant + policy.
 */
export function buildDiscoveryUrl(config: ConfigService): string | undefined {
  const explicit = config.get<string>('B2C_DISCOVERY_URL');
  if (explicit) {
    return explicit;
  }

  const tenant = config.get<string>('B2C_TENANT_NAME');
  const policy = config.get<string>('B2C_POLICY_NAME');
  if (!tenant || !policy) {
    return undefined;
  }

  return `https://${tenant}.b2clogin.com/${tenant}.onmicrosoft.com/${policy}/v2.0/.well-known/openid-configuration`;
}

/**
 * Inspects the environment without throwing, so the app still boots when B2C is
 * only half-configured and /setup can say exactly what is outstanding.
 *
 * B2C_CLIENT_SECRET is deliberately not required: a registration B2C treats as
 * a public client must not send one.
 */
export function inspectOidcConfig(config: ConfigService): {
  config: OidcConfig | null;
  status: OidcStatus;
} {
  const logger = new Logger('OidcConfig');

  const discoveryUrl = buildDiscoveryUrl(config);
  const clientId = config.get<string>('B2C_CLIENT_ID');
  const clientSecret = config.get<string>('B2C_CLIENT_SECRET');

  const baseUrl = config.get<string>('APP_BASE_URL') ?? 'http://localhost:3000';
  const redirectUri =
    config.get<string>('B2C_REDIRECT_URI') ?? `${baseUrl}/auth/callback`;
  const postLogoutRedirectUri =
    config.get<string>('B2C_POST_LOGOUT_REDIRECT_URI') ?? `${baseUrl}/`;

  const missing = [
    !discoveryUrl && 'B2C_DISCOVERY_URL (or B2C_TENANT_NAME + B2C_POLICY_NAME)',
    !clientId && 'B2C_CLIENT_ID',
  ].filter((entry): entry is string => Boolean(entry));

  if (missing.length > 0) {
    logger.warn(
      `Azure AD B2C is not configured — missing ${missing.join(', ')}. ` +
        'The app will start, but signing in is disabled until you fill in .env.',
    );

    return {
      config: null,
      status: {
        configured: false,
        missing,
        mode: null,
        discoveryUrl,
        redirectUri,
        postLogoutRedirectUri,
      },
    };
  }

  if (!clientSecret) {
    logger.log(
      'No B2C_CLIENT_SECRET set — configuring a public client (PKCE only). ' +
        'Register the redirect URI under the "Web" platform and set a secret ' +
        'to run as a confidential client instead.',
    );
  }

  return {
    config: {
      discoveryUrl: discoveryUrl as string,
      clientId: clientId as string,
      clientSecret: clientSecret || undefined,
      redirectUri,
      postLogoutRedirectUri,
      scope:
        config.get<string>('B2C_SCOPE') ?? 'openid profile email offline_access',
    },
    status: {
      configured: true,
      missing: [],
      mode: clientSecret ? 'confidential' : 'public',
      discoveryUrl,
      redirectUri,
      postLogoutRedirectUri,
    },
  };
}
