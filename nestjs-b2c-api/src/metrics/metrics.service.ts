import { Injectable } from '@nestjs/common';
import {
  Counter,
  Histogram,
  Registry,
  collectDefaultMetrics,
} from 'prom-client';

/**
 * Owns the Prometheus registry. Metric names follow the Prometheus convention
 * (`_total` on counters, base unit in the name) so the standard Grafana panels
 * and any Azure Managed Prometheus rules understand them without translation.
 */
@Injectable()
export class MetricsService {
  readonly registry = new Registry();

  /** API call volume, sliced the way the dashboard slices it. */
  readonly requests = new Counter({
    name: 'api_requests_total',
    help: 'API calls received, by route and outcome',
    labelNames: ['method', 'route', 'status', 'status_class'] as const,
    registers: [this.registry],
  });

  readonly duration = new Histogram({
    name: 'api_request_duration_seconds',
    help: 'API call latency',
    labelNames: ['method', 'route', 'status_class'] as const,
    // Tuned for an API that only validates a token and returns JSON; the top
    // bucket exists to catch a JWKS fetch stalling.
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5],
    registers: [this.registry],
  });

  /**
   * Why calls are refused. A rising `rejected` rate with a flat `accepted` rate
   * is the shape of a misconfigured client or an expired-token storm, and it is
   * invisible in a plain 4xx count.
   */
  readonly authResults = new Counter({
    name: 'api_auth_results_total',
    help: 'Bearer token validation outcomes',
    labelNames: ['result'] as const,
    registers: [this.registry],
  });

  constructor() {
    collectDefaultMetrics({ register: this.registry });
    // Touch the label sets that matter so panels show 0 rather than "No data"
    // before the first request of that kind arrives.
    this.authResults.inc({ result: 'accepted' }, 0);
    this.authResults.inc({ result: 'rejected' }, 0);
  }

  async scrape(): Promise<string> {
    return this.registry.metrics();
  }

  get contentType(): string {
    return this.registry.contentType;
  }
}
