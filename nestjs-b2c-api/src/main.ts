import 'reflect-metadata';

import { createServer } from 'node:http';

import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';

import { AppModule } from './app.module';
import { MetricsService } from './metrics/metrics.service';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);
  const config = app.get(ConfigService);

  // Stateless API: no sessions, no cookies, so nothing to protect against CSRF
  // and nothing for a browser to attach automatically.
  app.enableCors({
    origin: config.get<string>('CORS_ORIGIN') ?? 'http://localhost:3000',
    methods: ['GET'],
    allowedHeaders: ['Authorization'],
  });

  const port = Number(config.get<string>('PORT') ?? 3001);
  await app.listen(port, '0.0.0.0');

  const logger = new Logger('Bootstrap');
  logger.log(`API listening on http://localhost:${port}`);

  // Metrics live on their own port, so the public API keeps exactly one route
  // and scrape traffic never touches the authenticated surface. Publish this
  // port to Prometheus only, never to the internet.
  const metricsPort = Number(config.get<string>('METRICS_PORT') ?? 9464);
  const metrics = app.get(MetricsService);

  createServer((req, res) => {
    if (req.url?.split('?')[0] !== '/metrics') {
      res.writeHead(404).end();
      return;
    }
    metrics
      .scrape()
      .then((body) => {
        res.writeHead(200, { 'Content-Type': metrics.contentType }).end(body);
      })
      .catch(() => res.writeHead(500).end());
  }).listen(metricsPort, '0.0.0.0', () => {
    logger.log(`Metrics on http://localhost:${metricsPort}/metrics`);
  });
}

void bootstrap();
