import { Controller, Get, Render, Req, UseGuards } from '@nestjs/common';
import type { Request } from 'express';

import { AuthenticatedGuard } from '../auth/authenticated.guard';
import type { AppUser } from '../auth/user.model';
import { ApiDemoService } from './api-demo.service';

@Controller('api-demo')
export class ApiDemoController {
  constructor(private readonly api: ApiDemoService) {}

  /**
   * Deliberately sends no Authorization header even when the visitor is signed
   * in, so the link demonstrates exactly one thing: what the API does with an
   * anonymous caller.
   */
  @Get('anonymous')
  @Render('api-demo')
  async anonymous(@Req() req: Request) {
    const result = await this.api.call();

    return {
      title: 'API without a token',
      heading: 'Calling the API without a token',
      lede: 'No Authorization header was sent. The API should refuse this.',
      expectation: 'expect 401',
      isAuthenticated: req.isAuthenticated?.() ?? false,
      statusTone: tone(result.status),
      result,
    };
  }

  @Get('authorized')
  @UseGuards(AuthenticatedGuard)
  @Render('api-demo')
  async authorized(@Req() req: Request) {
    const user = req.user as AppUser;

    // Prefer the access token: that is what a downstream API is meant to
    // receive. B2C only issues one addressed to another API when that API's
    // scope was requested, so fall back to the ID token, which the API accepts
    // while its audience check is off.
    const token = user.accessToken ?? user.idToken;
    const kind = user.accessToken ? 'access token' : 'ID token';

    const result = await this.api.call(token, kind);

    return {
      title: 'API with your token',
      heading: 'Calling the API with your token',
      lede: `Your ${kind} from this session was sent as a bearer token.`,
      expectation: 'expect 200',
      isAuthenticated: true,
      statusTone: tone(result.status),
      result,
    };
  }
}

/** 2xx reads as success; everything else, including an expected 401, as a warning. */
function tone(status?: number): 'ok' | 'warn' {
  return status !== undefined && status >= 200 && status < 300 ? 'ok' : 'warn';
}
