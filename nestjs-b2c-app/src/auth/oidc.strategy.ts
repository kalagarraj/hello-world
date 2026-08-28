import { Logger } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { Client, Strategy, TokenSet } from 'openid-client';

import type { OidcConfig } from './oidc.config';
import { AppUser, toAppUser } from './user.model';

/**
 * Thin wrapper around the Passport strategy that ships with `openid-client`.
 * It performs the authorization code flow with PKCE against the Azure AD B2C
 * user flow, validates the ID token signature/claims against the tenant's JWKS,
 * and hands the resulting claims to `validate()`.
 */
export class OidcStrategy extends PassportStrategy(Strategy, 'oidc') {
  private readonly logger = new Logger(OidcStrategy.name);

  constructor(client: Client, oidc: OidcConfig) {
    super({
      client,
      params: {
        redirect_uri: oidc.redirectUri,
        scope: oidc.scope,
      },
      // B2C advertises S256 support; PKCE protects the code even though this
      // is a confidential client.
      usePKCE: 'S256',
      passReqToCallback: false,
    });
  }

  /**
   * `openid-client` merges anything it receives in `options` into the
   * authorization request query string. `@nestjs/passport` always supplies its
   * own `session`/`property` defaults, which would otherwise show up as bogus
   * parameters on the B2C authorize URL.
   */
  authenticate(req: unknown, options: Record<string, unknown> = {}): void {
    const { session, property, ...authorizationParams } = options;
    super.authenticate(req, authorizationParams);
  }

  /**
   * `openid-client` only calls the UserInfo endpoint when the verify callback
   * declares more parameters than the token set; B2C user flows do not expose a
   * useful UserInfo endpoint, so everything we need comes from the ID token.
   */
  validate(tokenset: TokenSet): AppUser {
    const claims = tokenset.claims();
    this.logger.log(`Signed in subject ${claims.sub}`);
    return toAppUser(claims, tokenset.id_token);
  }
}
