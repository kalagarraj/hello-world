import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/**
 * What this API needs in order to validate a bearer token that Azure AD B2C
 * issued to a client application.
 */
export interface B2cApiConfig {
  discoveryUrl: string;
  /**
   * Optional. When set, a token is accepted only if its `aud` claim matches,
   * which is what stops a token minted for a different application being
   * replayed here. Left unset, any token the tenant signed is accepted --
   * convenient, and a real weakening. See the README.
   */
  audience?: string;
  /** Optional: also require this scope in the token's `scp` claim. */
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
 * Only the tenant is required: with just a discovery URL the API accepts any
 * unexpired token that tenant signed, which is what lets the web app's existing
 * bearer token work with no extra app registration.
 *
 * It still refuses to start without that. An API with no way to validate
 * tokens can only reject everything, or accept everything.
 */
export function loadB2cApiConfig(config: ConfigService): B2cApiConfig {
  const logger = new Logger('B2cApiConfig');

  const discoveryUrl = buildDiscoveryUrl(config);
  if (!discoveryUrl) {
    throw new Error(
      'Cannot start: set B2C_DISCOVERY_URL, or B2C_TENANT_NAME and ' +
        'B2C_POLICY_NAME. Without a tenant there is no key to validate ' +
        'tokens against.',
    );
  }

  const audience = config.get<string>('B2C_API_AUDIENCE');
  const requiredScope = config.get<string>('B2C_REQUIRED_SCOPE');

  if (audience) {
    logger.log(`Requiring audience ${audience}`);
  } else {
    // Loud, because this is the difference between "tokens meant for me" and
    // "any token from this tenant", and it must not reach production silently.
    logger.warn(
      'B2C_API_AUDIENCE is not set: ANY unexpired token signed by this tenant ' +
        'is accepted, including tokens issued to other applications. Fine for ' +
        'local development; set it before deploying.',
    );
  }

  logger.log(
    requiredScope ? `Requiring scope ${requiredScope}` : 'No scope check',
  );

  return { discoveryUrl, audience, requiredScope };
}
