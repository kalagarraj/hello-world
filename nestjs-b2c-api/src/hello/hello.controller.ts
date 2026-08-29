import { Controller, Get, Req, UseGuards } from '@nestjs/common';
import type { Request } from 'express';

import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import type { BearerPrincipal } from '../auth/jwt.strategy';

@Controller()
export class HelloController {
  /**
   * The API's only endpoint. Reachable solely with a valid Azure AD B2C bearer
   * token; anything else gets a 401 before this method runs.
   */
  @Get('hello')
  @UseGuards(JwtAuthGuard)
  hello(@Req() req: Request) {
    const caller = req.user as BearerPrincipal;

    return {
      message: 'Hello from the new app',
      caller: {
        subject: caller.subject,
        name: caller.name,
        email: caller.email,
        scopes: caller.scopes,
      },
      tokenIssuedBy: caller.issuer,
    };
  }
}
