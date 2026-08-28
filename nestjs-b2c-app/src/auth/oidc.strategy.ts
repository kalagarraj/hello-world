import { PassportStrategy } from '@nestjs/passport';
import type { Request } from 'express';
import { Client, Strategy, TokenSet } from 'openid-client';

import { authFlow, flowId, tokenSummary } from './auth-flow.logger';
import type { OidcConfig } from './oidc.config';
import { AppUser, toAppUser } from './user.model';

/**
 * Thin wrapper around the Passport strategy that ships with `openid-client`.
 * It performs the authorization code flow with PKCE against the Azure AD B2C
 * user flow, validates the ID token signature/claims against the tenant's JWKS,
 * and hands the resulting claims to `validate()`.
 */
export class OidcStrategy extends PassportStrategy(Strategy, 'oidc') {
  constructor(
    private readonly client: Client,
    private readonly oidc: OidcConfig,
  ) {
    super({
      client,
      params: {
        redirect_uri: oidc.redirectUri,
        scope: oidc.scope,
      },
      // B2C advertises S256 support; PKCE protects the code even though this
      // is a confidential client.
      usePKCE: 'S256',
      // Gives validate() the request, so the token-exchange steps carry the
      // same correlation id as the redirect legs.
      passReqToCallback: true,
    });
  }

  /**
   * `openid-client` merges anything it receives in `options` into the
   * authorization request query string. `@nestjs/passport` always supplies its
   * own `session`/`property` defaults, which would otherwise show up as bogus
   * parameters on the B2C authorize URL.
   */
  authenticate(req: Request, options: Record<string, unknown> = {}): void {
    const { session, property, ...authorizationParams } = options;

    // The same strategy handles both legs: the outbound redirect, and the
    // return trip carrying ?code=.
    if (req.query?.code || req.query?.error) {
      authFlow('2. CALLBACK', {
        flow: flowId(req),
        code: req.query.code ? 'received' : 'absent',
        state: req.query.state ? 'returned' : 'absent',
        error: req.query.error ?? undefined,
      });
      authFlow('3. TOKEN EXCHANGE', {
        flow: flowId(req),
        endpoint: this.client.issuer.metadata.token_endpoint,
        auth_method: this.oidc.clientSecret ? 'client_secret_post' : 'none (PKCE only)',
      });
    } else {
      authFlow('1. LOGIN START', {
        flow: flowId(req),
        endpoint: this.client.issuer.metadata.authorization_endpoint,
        scope: this.oidc.scope,
        redirect_uri: this.oidc.redirectUri,
        pkce: 'S256',
      });
    }

    super.authenticate(req, authorizationParams);
  }

  /**
   * `openid-client` only calls the UserInfo endpoint when the verify callback
   * declares more parameters than (req, tokenset); B2C user flows do not expose
   * a useful UserInfo endpoint, so everything we need comes from the ID token.
   */
  validate(req: Request, tokenset: TokenSet): AppUser {
    const flow = flowId(req);

    authFlow('4. TOKENS RECEIVED', {
      flow,
      id_token: tokenSummary(tokenset.id_token),
      access_token: tokenSummary(tokenset.access_token),
      refresh_token: tokenSummary(tokenset.refresh_token),
      expires_in: tokenset.expires_in,
    });

    // openid-client has already verified the signature against the tenant JWKS
    // and checked iss / aud / exp / nonce by this point.
    const claims = tokenset.claims();
    authFlow('5. ID TOKEN VALID', {
      flow,
      iss: claims.iss,
      aud: claims.aud,
      sub: claims.sub,
      claims: `[${Object.keys(claims).join(', ')}]`,
    });

    const user = toAppUser(claims, tokenset.id_token);
    authFlow('6. USER MAPPED', {
      flow,
      name: user.name,
      email: user.email ?? '(no email claim)',
      idp: user.identityProvider,
      policy: user.policy,
    });

    return user;
  }
}
