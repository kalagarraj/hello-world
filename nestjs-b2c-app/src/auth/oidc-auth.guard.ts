import { ExecutionContext, Inject, Injectable, Optional } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import type { Request, Response } from 'express';

import { OIDC_CONFIG, type OidcConfig } from './oidc.config';

/**
 * Kicks off the redirect to Azure AD B2C and, on the way back, persists the
 * authenticated user in the session.
 */
@Injectable()
export class OidcAuthGuard extends AuthGuard('oidc') {
  constructor(
    @Optional() @Inject(OIDC_CONFIG) private readonly oidc: OidcConfig | null,
  ) {
    super();
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    if (!this.oidc) {
      context.switchToHttp().getResponse<Response>().redirect('/setup');
      return false;
    }

    const result = (await super.canActivate(context)) as boolean;
    await super.logIn(context.switchToHttp().getRequest<Request>());
    return result;
  }
}
