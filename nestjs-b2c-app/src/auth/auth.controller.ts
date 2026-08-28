import { Controller, Get, Inject, Optional, Req, Res, UseGuards } from '@nestjs/common';
import type { Request, Response } from 'express';
import type { Client } from 'openid-client';

import { AuthenticatedGuard } from './authenticated.guard';
import { OIDC_CLIENT, OIDC_CONFIG, type OidcConfig } from './oidc.config';
import { OidcAuthGuard } from './oidc-auth.guard';
import type { AppUser } from './user.model';

@Controller('auth')
export class AuthController {
  constructor(
    @Optional() @Inject(OIDC_CONFIG) private readonly oidc: OidcConfig | null,
    @Optional() @Inject(OIDC_CLIENT) private readonly client: Client | null,
  ) {}

  /**
   * The guard never returns here: Passport writes the 302 to the B2C
   * authorize endpoint (with state, nonce and the PKCE challenge).
   */
  @Get('login')
  @UseGuards(OidcAuthGuard)
  login(): void {
    return;
  }

  /**
   * B2C redirects back here with `?code=...`. The guard exchanges the code for
   * tokens, validates the ID token and stores the user in the session.
   */
  @Get('callback')
  @UseGuards(OidcAuthGuard)
  callback(@Res() res: Response): void {
    res.redirect('/welcome');
  }

  /** Clears the local session, then ends the session at B2C as well. */
  @Get('logout')
  @UseGuards(AuthenticatedGuard)
  logout(@Req() req: Request, @Res() res: Response): void {
    const user = req.user as AppUser | undefined;
    const idTokenHint = user?.idToken;

    req.logout((logoutError) => {
      if (logoutError) {
        throw logoutError;
      }

      req.session.destroy(() => {
        res.clearCookie('b2c.sid');

        if (!this.client || !this.oidc) {
          res.redirect('/');
          return;
        }

        res.redirect(
          this.client.endSessionUrl({
            id_token_hint: idTokenHint,
            post_logout_redirect_uri: this.oidc.postLogoutRedirectUri,
          }),
        );
      });
    });
  }
}
