import { ConfigService } from '@nestjs/config';

/**
 * Where session state lives. The default (`auto`) resolves to Redis whenever a
 * REDIS_URL is present and to the in-process store otherwise, so a developer
 * needs no infrastructure while every deployed environment gets a shared store.
 */
export type SessionStoreKind = 'memory' | 'redis';

export interface SessionSettings {
  /** Logical environment: local, dev, test, prod, ... */
  appEnv: string;
  isLocal: boolean;
  store: SessionStoreKind;
  redisUrl?: string;
  /** Namespaces keys so environments sharing one cache cannot collide. */
  keyPrefix: string;
  secret: string;
  cookieName: string;
  cookieSecure: boolean;
  maxAgeMs: number;
  /** Escape hatch: allow the in-process store outside local. */
  allowMemoryOutsideLocal: boolean;
}

function asBoolean(value: string | undefined, fallback: boolean): boolean {
  if (value === undefined) {
    return fallback;
  }
  return ['1', 'true', 'yes', 'on'].includes(value.toLowerCase());
}

export function loadSessionSettings(config: ConfigService): SessionSettings {
  const appEnv = (config.get<string>('APP_ENV') ?? 'local').toLowerCase();
  const isLocal = appEnv === 'local';

  const redisUrl = config.get<string>('REDIS_URL');
  const requested = (
    config.get<string>('SESSION_STORE') ?? 'auto'
  ).toLowerCase();

  let store: SessionStoreKind;
  if (requested === 'redis' || requested === 'memory') {
    store = requested;
  } else {
    store = redisUrl ? 'redis' : 'memory';
  }

  return {
    appEnv,
    isLocal,
    store,
    redisUrl,
    keyPrefix: config.get<string>('SESSION_KEY_PREFIX') ?? `sess:${appEnv}:`,
    secret: config.get<string>('SESSION_SECRET') ?? 'dev-only-insecure-secret',
    cookieName: config.get<string>('SESSION_COOKIE_NAME') ?? 'b2c.sid',
    // Azure terminates TLS at the front door, so anything deployed is https.
    cookieSecure: asBoolean(config.get<string>('SESSION_COOKIE_SECURE'), !isLocal),
    maxAgeMs: Number(config.get<string>('SESSION_MAX_AGE_MS') ?? 60 * 60 * 1000),
    allowMemoryOutsideLocal: asBoolean(
      config.get<string>('SESSION_ALLOW_MEMORY_STORE'),
      false,
    ),
  };
}
