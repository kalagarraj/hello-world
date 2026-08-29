import { Injectable, NestMiddleware } from '@nestjs/common';
import type { NextFunction, Request, Response } from 'express';

import { MetricsService } from './metrics.service';

/**
 * Records every API call.
 *
 * This is middleware rather than an interceptor on purpose. Nest runs guards
 * *before* interceptors, so a request the auth guard rejects never reaches an
 * interceptor: with that design the 401s -- the single most interesting signal
 * on a token-protected API -- were silently counted as nothing. Middleware runs
 * first and records on the response's `finish` event, so it sees every reply
 * whatever produced it: guard rejection, unmatched route, handler, or
 * exception filter.
 */
@Injectable()
export class MetricsMiddleware implements NestMiddleware {
  constructor(private readonly metrics: MetricsService) {}

  use(request: Request, response: Response, next: NextFunction): void {
    const started = process.hrtime.bigint();

    response.on('finish', () => {
      const seconds = Number(process.hrtime.bigint() - started) / 1e9;
      const status = response.statusCode;
      const statusClass = `${Math.floor(status / 100)}xx`;

      // By `finish` the router has run, so the matched pattern is available.
      // Anything unmatched is bucketed rather than labelled with its raw URL,
      // which would mint a time series per scanned path.
      const route = request.route?.path ?? 'unmatched';
      const method = request.method;

      this.metrics.requests.inc({
        method,
        route,
        status: String(status),
        status_class: statusClass,
      });
      this.metrics.duration.observe(
        { method, route, status_class: statusClass },
        seconds,
      );
      this.metrics.authResults.inc({
        result: status === 401 || status === 403 ? 'rejected' : 'accepted',
      });
    });

    next();
  }
}
