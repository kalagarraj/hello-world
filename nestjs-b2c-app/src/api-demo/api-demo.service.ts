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
      // A refused connection is the common case here -- the API simply is not
      // running -- and is worth distinguishing from a rejection by the API.
      result.transportError =
        error instanceof Error ? error.message : String(error);
      this.logger.warn(`Could not reach ${url}: ${result.transportError}`);
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
