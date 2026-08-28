import { Logger } from '@nestjs/common';
import { RedisStore } from 'connect-redis';
import session from 'express-session';
import type { RequestHandler } from 'express';
import { createClient, type RedisClientType } from 'redis';

import type { SessionSettings } from './session.config';

const logger = new Logger('SessionStore');

export interface SessionMiddleware {
  handler: RequestHandler;
  /** Present only for the Redis store; closed on shutdown. */
  close: () => Promise<void>;
}

/**
 * Builds the express-session middleware with a store chosen per environment:
 * the in-process store locally, Azure Cache for Redis everywhere else.
 */
export async function createSessionMiddleware(
  settings: SessionSettings,
): Promise<SessionMiddleware> {
  const { store, handlerStore, close } = await resolveStore(settings);

  logger.log(
    `env=${settings.appEnv} store=${store} prefix=${settings.keyPrefix} secure_cookie=${settings.cookieSecure}`,
  );

  const handler = session({
    name: settings.cookieName,
    secret: settings.secret,
    store: handlerStore,
    resave: false,
    saveUninitialized: false,
    cookie: {
      httpOnly: true,
      sameSite: 'lax',
      secure: settings.cookieSecure,
      maxAge: settings.maxAgeMs,
    },
  });

  return { handler, close };
}

async function resolveStore(settings: SessionSettings): Promise<{
  store: string;
  handlerStore?: session.Store;
  close: () => Promise<void>;
}> {
  if (settings.store === 'memory') {
    // The in-process store loses every session on restart and is not shared
    // between instances, so it is a local-only convenience. Failing loudly
    // beats discovering in production that users are randomly signed out.
    if (!settings.isLocal && !settings.allowMemoryOutsideLocal) {
      throw new Error(
        `APP_ENV=${settings.appEnv} resolved to the in-memory session store. ` +
          'Set REDIS_URL to point at Azure Cache for Redis, or set ' +
          'SESSION_ALLOW_MEMORY_STORE=true to accept sessions that are lost on ' +
          'restart and unusable across multiple instances.',
      );
    }

    if (!settings.isLocal) {
      logger.warn(
        `APP_ENV=${settings.appEnv} is using the in-memory session store because ` +
          'SESSION_ALLOW_MEMORY_STORE is set. Sessions will not survive a ' +
          'restart or be shared across instances.',
      );
    }

    return { store: 'memory', handlerStore: undefined, close: async () => {} };
  }

  if (!settings.redisUrl) {
    throw new Error(
      'SESSION_STORE=redis but REDIS_URL is not set. Azure Cache for Redis ' +
        'requires TLS, so the URL looks like ' +
        'rediss://:<access-key>@<name>.redis.cache.windows.net:6380',
    );
  }

  const client: RedisClientType = createClient({
    url: settings.redisUrl,
    socket: {
      // Azure closes idle connections; reconnect with backoff rather than
      // failing the next request that needs a session.
      reconnectStrategy: (retries) => Math.min(retries * 200, 5000),
    },
  });

  client.on('error', (error: Error) => {
    logger.error(`Redis client error: ${error.message}`);
  });
  client.on('reconnecting', () => logger.warn('Reconnecting to Redis...'));

  // Connect during bootstrap so a bad URL or firewall rule fails the deploy
  // rather than every user's sign-in.
  await client.connect();
  logger.log(`Connected to Redis for ${settings.appEnv} sessions`);

  return {
    store: 'redis',
    handlerStore: new RedisStore({
      client,
      prefix: settings.keyPrefix,
      ttl: Math.floor(settings.maxAgeMs / 1000),
    }),
    close: async () => {
      await client.quit();
    },
  };
}
