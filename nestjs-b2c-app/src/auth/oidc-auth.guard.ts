import { ExecutionContext, Inject, Injectable, Optional } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import type { Request, Response } from 'express';

import { authFlow, flowId } from './auth-flow.logger';
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
    const request = context.switchToHttp().getRequest<Request>();

    if (!this.oidc) {
      authFlow('LOGIN BLOCKED', {
        reason: 'Azure AD B2C is not configured',
        redirect: '/setup',
      });
      context.switchToHttp().getResponse<Response>().redirect('/setup');
      return false;
    }

    const result = (await super.canActivate(context)) as boolean;

    // Passport regenerates the session on login to defeat session fixation, so
    // the correlation id changes here. Log both halves to keep the trace
    // followable across the rotation.
    const before = flowId(request);
    await super.logIn(request);

    authFlow('8. LOGIN COMPLETE', {
      flow: `${before} -> ${flowId(request)}`,
      session: 'regenerated (fixation defence)',
      authenticated: request.isAuthenticated?.() ?? false,
      next: '/welcome',
    });
    return result;
  }
}
