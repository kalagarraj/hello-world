import 'reflect-metadata';

import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';

import { AppModule } from './app.module';

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

  new Logger('Bootstrap').log(`API listening on http://localhost:${port}`);
}

void bootstrap();
