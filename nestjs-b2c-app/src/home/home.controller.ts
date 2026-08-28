import { Controller, Get, Inject, Optional, Query, Req, Render, UseGuards } from '@nestjs/common';
import type { Request } from 'express';

import { AuthenticatedGuard } from '../auth/authenticated.guard';
import {
  OIDC_CONFIG,
  OIDC_STATUS,
  type OidcConfig,
  type OidcStatus,
} from '../auth/oidc.config';
import type { AppUser } from '../auth/user.model';

const ERROR_MESSAGES: Record<string, string> = {
  signin_required: 'Please sign in to see the welcome page.',
};

@Controller()
export class HomeController {
  constructor(
    @Optional() @Inject(OIDC_CONFIG) private readonly oidc: OidcConfig | null,
    @Optional() @Inject(OIDC_STATUS) private readonly status: OidcStatus | null,
  ) {}

  @Get()
  @Render('home')
  home(@Req() req: Request, @Query('error') error?: string) {
    return {
      title: 'Hello World',
      isConfigured: this.oidc !== null,
      isAuthenticated: req.isAuthenticated?.() ?? false,
      user: req.user as AppUser | undefined,
      error: error ? (ERROR_MESSAGES[error] ?? error) : undefined,
    };
  }

  @Get('welcome')
  @UseGuards(AuthenticatedGuard)
  @Render('welcome')
  welcome(@Req() req: Request) {
    const user = req.user as AppUser;

    return {
      title: 'Welcome',
      user,
      details: [
        { label: 'Display name', value: user.name },
        { label: 'Email', value: user.email },
        { label: 'Given name', value: user.givenName },
        { label: 'Family name', value: user.familyName },
        { label: 'User ID (oid/sub)', value: user.id },
        { label: 'Identity provider', value: user.identityProvider },
        { label: 'User flow (policy)', value: user.policy },
        { label: 'Token issued at', value: formatTimestamp(user.issuedAt) },
        { label: 'Token expires at', value: formatTimestamp(user.expiresAt) },
      ].filter((detail) => Boolean(detail.value)),
      claimsJson: JSON.stringify(redactClaims(user.claims), null, 2),
    };
  }

  @Get('setup')
  @Render('setup')
  setup() {
    return {
      title: 'Finish setup',
      isConfigured: this.oidc !== null,
      missing: this.status?.missing ?? [],
      mode: this.status?.mode,
      discoveryUrl: this.status?.discoveryUrl,
      redirectUri: this.status?.redirectUri ?? 'http://localhost:3000/auth/callback',
      postLogoutRedirectUri: this.status?.postLogoutRedirectUri ?? 'http://localhost:3000/',
    };
  }

  @Get('healthz')
  health() {
    return { status: 'ok', b2cConfigured: this.oidc !== null };
  }
}

function formatTimestamp(seconds?: number): string | undefined {
  return seconds ? new Date(seconds * 1000).toISOString() : undefined;
}

/** The raw claim dump is shown on the page, so drop anything token-shaped. */
function redactClaims(claims: Record<string, unknown>): Record<string, unknown> {
  const { at_hash, c_hash, nonce, ...rest } = claims;
  return rest;
}
