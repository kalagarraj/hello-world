import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import type { Request, Response } from 'express';

/**
 * Protects pages that require a signed-in user. Browsers get a redirect to the
 * home page rather than a 401 body.
 */
@Injectable()
export class AuthenticatedGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<Request>();
    if (request.isAuthenticated?.()) {
      return true;
    }

    context.switchToHttp().getResponse<Response>().redirect('/?error=signin_required');
    return false;
  }
}
