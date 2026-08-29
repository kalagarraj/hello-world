import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/**
 * What this API needs in order to validate a bearer token that Azure AD B2C
 * issued to a client application.
 */
export interface B2cApiConfig {
  discoveryUrl: string;
  /**
   * Application (client) ID of the API's own app registration. A token is
   * accepted only when its `aud` claim matches, which is what stops a token
   * minted for some other API from being replayed here.
   */
  audience: string;
  /** Optional: require this scope in the token's `scp` claim. */
  requiredScope?: string;
}

export const B2C_CONFIG = 'B2C_CONFIG';
export const B2C_ISSUER = 'B2C_ISSUER';
export const JWT_STRATEGY = 'JWT_STRATEGY';

export interface B2cIssuerMetadata {
  issuer: string;
  jwksUri: string;
}

/** Same shape the web app derives, so both point at one user flow. */
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
 * Unlike the web app, this one refuses to start when it is unconfigured. A web
 * app with no identity provider can still serve a public page; an API with no
 * way to validate tokens can only either reject everything or, far worse,
 * accept everything.
 */
export function loadB2cApiConfig(config: ConfigService): B2cApiConfig {
  const logger = new Logger('B2cApiConfig');

  const discoveryUrl = buildDiscoveryUrl(config);
  const audience = config.get<string>('B2C_API_AUDIENCE');

  const missing = [
    !discoveryUrl && 'B2C_DISCOVERY_URL (or B2C_TENANT_NAME + B2C_POLICY_NAME)',
    !audience && 'B2C_API_AUDIENCE',
  ].filter((entry): entry is string => Boolean(entry));

  if (missing.length > 0) {
    throw new Error(
      `Cannot start: missing ${missing.join(', ')}. An API without token ` +
        'validation configured would have to reject every request, so this ' +
        'fails at startup rather than at runtime.',
    );
  }

  const requiredScope = config.get<string>('B2C_REQUIRED_SCOPE');
  logger.log(
    `Accepting tokens for audience ${audience}` +
      (requiredScope ? ` with scope ${requiredScope}` : ' (no scope check)'),
  );

  return {
    discoveryUrl: discoveryUrl as string,
    audience: audience as string,
    requiredScope,
  };
}
