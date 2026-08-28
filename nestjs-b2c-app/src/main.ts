import 'reflect-metadata';

import { join } from 'node:path';

import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import passport from 'passport';

import { AppModule } from './app.module';
import { loadSessionSettings } from './session/session.config';
import { createSessionMiddleware } from './session/session.factory';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);
  const config = app.get(ConfigService);

  // Behind Azure App Service / Container Apps the TLS terminator sets
  // X-Forwarded-Proto; trusting it keeps the session cookie `secure` flag sane.
  app.set('trust proxy', 1);

  app.useStaticAssets(join(__dirname, '..', 'public'), { prefix: '/static/' });
  app.setBaseViewsDir(join(__dirname, '..', 'views'));
  app.setViewEngine('hbs');
  // Every view is wrapped by views/layouts/main.hbs, which renders {{{body}}}.
  app.set('view options', { layout: 'layouts/main' });

  // Local runs keep sessions in process; every deployed environment gets a
  // shared store so sessions survive restarts and scale-out.
  const sessionSettings = loadSessionSettings(config);
  const sessions = await createSessionMiddleware(sessionSettings);

  // Release the Redis connection on the way out so Azure does not leave the
  // socket dangling across a restart or scale-in.
  for (const signal of ['SIGINT', 'SIGTERM'] as const) {
    process.once(signal, () => {
      void app
        .close()
        .then(() => sessions.close())
        .finally(() => process.exit(0));
    });
  }

  app.use(sessions.handler);
  app.use(passport.initialize());
  app.use(passport.session());

  const port = Number(config.get<string>('PORT') ?? 3000);
  await app.listen(port, '0.0.0.0');

  new Logger('Bootstrap').log(`Listening on http://localhost:${port}`);
}

void bootstrap();
