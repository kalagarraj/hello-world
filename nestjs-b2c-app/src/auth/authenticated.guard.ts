import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import type { Request, Response } from 'express';

import { authFlow, flowId } from './auth-flow.logger';

/**
 * Protects pages that require a signed-in user. Browsers get a redirect to the
 * home page rather than a 401 body.
 */
@Injectable()
export class AuthenticatedGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<Request>();

    if (request.isAuthenticated?.()) {
      authFlow('AUTHZ ALLOW', {
        flow: flowId(request),
        route: `${request.method} ${request.path}`,
        user: (request.user as { name?: string } | undefined)?.name,
      });
      return true;
    }

    authFlow('AUTHZ DENY', {
      flow: flowId(request),
      route: `${request.method} ${request.path}`,
      reason: 'no authenticated session',
      redirect: '/?error=signin_required',
    });
    context.switchToHttp().getResponse<Response>().redirect('/?error=signin_required');
    return false;
  }
}
