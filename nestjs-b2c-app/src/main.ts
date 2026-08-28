import 'reflect-metadata';

import { join } from 'node:path';

import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import session from 'express-session';
import passport from 'passport';

import { AppModule } from './app.module';

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

  const isProduction = config.get<string>('NODE_ENV') === 'production';

  app.use(
    session({
      name: 'b2c.sid',
      secret: config.get<string>('SESSION_SECRET') ?? 'dev-only-insecure-secret',
      resave: false,
      saveUninitialized: false,
      cookie: {
        httpOnly: true,
        sameSite: 'lax',
        secure: isProduction,
        maxAge: 60 * 60 * 1000,
      },
    }),
  );
  app.use(passport.initialize());
  app.use(passport.session());

  const port = Number(config.get<string>('PORT') ?? 3000);
  await app.listen(port, '0.0.0.0');

  new Logger('Bootstrap').log(`Listening on http://localhost:${port}`);
}

void bootstrap();
