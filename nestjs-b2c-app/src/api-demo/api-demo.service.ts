import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import { authFlow } from '../auth/auth-flow.logger';

export interface ApiCallResult {
  url: string;
  sentToken: boolean;
  /** First and last few characters only -- never the whole token. */
  tokenPreview?: string;
  tokenKind?: 'access token' | 'ID token';
  status?: number;
  statusText?: string;
  body?: string;
  /** Set when the API could not be reached at all. */
  transportError?: string;
  /** The likeliest cause, chosen from the error code and the URL. */
  transportHint?: string;
}

/**
 * Calls the companion API from the server rather than the browser, so the
 * token is never handed to page scripts.
 */
@Injectable()
export class ApiDemoService {
  private readonly logger = new Logger(ApiDemoService.name);

  constructor(private readonly config: ConfigService) {}

  get apiUrl(): string {
    return this.config.get<string>('DEMO_API_URL') ?? 'http://localhost:3001/hello';
  }

  async call(token?: string, kind?: ApiCallResult['tokenKind']): Promise<ApiCallResult> {
    const url = this.apiUrl;
    const result: ApiCallResult = {
      url,
      sentToken: Boolean(token),
      tokenKind: token ? kind : undefined,
      tokenPreview: token ? preview(token) : undefined,
    };

    authFlow('API CALL', {
      url,
      authorization: token ? `Bearer ${preview(token)}` : 'omitted',
    });

    try {
      const response = await fetch(url, {
        headers: token ? { Authorization: `Bearer ${token}` } : {},
        signal: AbortSignal.timeout(5000),
      });

      result.status = response.status;
      result.statusText = response.statusText;
      result.body = await prettyBody(response);

      authFlow('API RESPONSE', { status: response.status, sent_token: Boolean(token) });
    } catch (error) {
      // Node's fetch reports every transport failure as the useless string
      // "fetch failed" and puts the real reason in `cause`. Surfacing the code
      // is the difference between a message that names the problem and one that
      // sends you hunting.
      const cause = (error as { cause?: NodeJS.ErrnoException }).cause;
      const code = cause?.code;
      const detail = code ?? cause?.message ?? (error as Error).message;

      result.transportError = detail;
      result.transportHint = hintFor(code, url);
      this.logger.warn(`Could not reach ${url}: ${detail}`);
    }

    return result;
  }
}

function preview(token: string): string {
  return token.length <= 24
    ? token
    : `${token.slice(0, 12)}…${token.slice(-8)} (${token.length} chars)`;
}

async function prettyBody(response: Response): Promise<string> {
  const text = await response.text();
  try {
    return JSON.stringify(JSON.parse(text), null, 2);
  } catch {
    return text || '(empty body)';
  }
}

/**
 * The two failure modes that actually happen here are a stopped API and a
 * containerised caller pointing at its own loopback, and they need different
 * fixes -- so the page should say which one it is looking at.
 */
function hintFor(code: string | undefined, url: string): string {
  const isLoopback = /\/\/(localhost|127\.0\.0\.1|\[::1\])[:/]/.test(url);

  if (code === 'ECONNREFUSED' && isLoopback) {
    return (
      'Nothing is listening on that port from where this app is running. If ' +
      'this app is itself in a container, localhost is the container, not your ' +
      'machine: point DEMO_API_URL at the API service name on a shared Docker ' +
      'network, or at host.docker.internal. Otherwise start the API.'
    );
  }
  if (code === 'ENOTFOUND' || code === 'EAI_AGAIN') {
    return 'That host name does not resolve from where this app is running. Check DEMO_API_URL, and that both containers share a network.';
  }
  if (code === 'UND_ERR_CONNECT_TIMEOUT' || code === 'ETIMEDOUT') {
    return 'The connection timed out rather than being refused, which usually means a firewall or a wrong host rather than a stopped API.';
  }
  return 'Check that the API is running and that DEMO_API_URL is reachable from this process.';
}
