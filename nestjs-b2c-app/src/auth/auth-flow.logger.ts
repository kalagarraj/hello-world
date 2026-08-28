import { Logger } from '@nestjs/common';
import type { Request } from 'express';

/**
 * Traces the authentication and authorization flow step by step, so the
 * redirect dance with Azure AD B2C can be followed in the console.
 *
 * Nothing secret is ever written here: authorization codes, PKCE verifiers,
 * tokens and the client secret are reported as presence/length only. Claim
 * values are logged because the welcome page already displays them, but the
 * raw ID token is not.
 *
 * Set AUTH_TRACE=false to silence it.
 */
const logger = new Logger('AuthFlow');

const STEP_WIDTH = 20;

function isEnabled(): boolean {
  return (process.env.AUTH_TRACE ?? 'true').toLowerCase() !== 'false';
}

/** Short, stable correlation key: every leg of one login shares a session. */
export function flowId(req: Partial<Request> & { sessionID?: string }): string {
  return req?.sessionID ? req.sessionID.slice(0, 8) : 'no-session';
}

export function authFlow(
  step: string,
  detail: Record<string, unknown> = {},
): void {
  if (!isEnabled()) {
    return;
  }

  const fields = Object.entries(detail)
    .filter(([, value]) => value !== undefined && value !== null)
    .map(([key, value]) => `${key}=${value}`)
    .join(' ');

  logger.log(`${step.padEnd(STEP_WIDTH)}${fields}`);
}

/** Reports a token's presence and size without ever printing the token. */
export function tokenSummary(token?: string): string {
  return token ? `yes(${token.length} chars)` : 'no';
}
