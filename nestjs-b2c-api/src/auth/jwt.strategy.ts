import { ForbiddenException, Logger } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy, type StrategyOptionsWithSecret } from 'passport-jwt';
import { passportJwtSecret } from 'jwks-rsa';

import type { B2cApiConfig, B2cIssuerMetadata } from './b2c.config';

/** What the API knows about the caller once a token has been validated. */
export interface BearerPrincipal {
  subject: string;
  name?: string;
  email?: string;
  scopes: string[];
  audience: string;
  issuer: string;
  expiresAt?: number;
}

interface B2cAccessTokenClaims {
  sub: string;
  aud: string;
  iss: string;
  exp?: number;
  scp?: string;
  name?: string;
  emails?: string[];
  email?: string;
  oid?: string;
}

/**
 * Validates the bearer token on every request: signature against the tenant's
 * JWKS, plus issuer, audience and expiry. Keys are fetched from the discovered
 * jwks_uri and cached, so a rotated signing key is picked up without a restart.
 */
export class JwtStrategy extends PassportStrategy(Strategy, 'jwt') {
  private readonly logger = new Logger(JwtStrategy.name);

  constructor(
    private readonly b2c: B2cApiConfig,
    issuerMetadata: B2cIssuerMetadata,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      // Never accept an expired token, whatever the clock skew.
      ignoreExpiration: false,
      algorithms: ['RS256'],
      issuer: issuerMetadata.issuer,
      audience: b2c.audience,
      secretOrKeyProvider: passportJwtSecret({
        jwksUri: issuerMetadata.jwksUri,
        cache: true,
        cacheMaxEntries: 5,
        cacheMaxAge: 10 * 60 * 1000,
        // A token with an unknown kid should not become a way to hammer the
        // tenant's JWKS endpoint.
        rateLimit: true,
        jwksRequestsPerMinute: 10,
      }),
    } as StrategyOptionsWithSecret);
  }

  /**
   * Reached only after the signature, issuer, audience and expiry all check
   * out. Scope enforcement is the one thing left, and it is authorization
   * rather than authentication: the caller is who they say, but may not be
   * allowed here.
   */
  validate(claims: B2cAccessTokenClaims): BearerPrincipal {
    const scopes = claims.scp ? claims.scp.split(' ').filter(Boolean) : [];

    if (this.b2c.requiredScope && !scopes.includes(this.b2c.requiredScope)) {
      this.logger.warn(
        `Rejected ${claims.sub}: scope ${this.b2c.requiredScope} not in [${scopes.join(', ')}]`,
      );
      throw new ForbiddenException(
        `Token is missing the required scope '${this.b2c.requiredScope}'`,
      );
    }

    return {
      subject: claims.oid ?? claims.sub,
      name: claims.name,
      email: Array.isArray(claims.emails) ? claims.emails[0] : claims.email,
      scopes,
      audience: claims.aud,
      issuer: claims.iss,
      expiresAt: claims.exp,
    };
  }
}
