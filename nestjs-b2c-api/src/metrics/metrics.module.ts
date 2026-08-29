import { Global, MiddlewareConsumer, Module, NestModule } from '@nestjs/common';

import { MetricsMiddleware } from './metrics.middleware';
import { MetricsService } from './metrics.service';

/**
 * Global, and applied to every path, so a route added later cannot be silently
 * missed by the dashboard.
 */
@Global()
@Module({
  providers: [MetricsService],
  exports: [MetricsService],
})
export class MetricsModule implements NestModule {
  configure(consumer: MiddlewareConsumer): void {
    consumer.apply(MetricsMiddleware).forRoutes('*');
  }
}
