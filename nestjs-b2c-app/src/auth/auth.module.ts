import { Logger, Module, Provider } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { PassportModule } from '@nestjs/passport';
import { Client, Issuer } from 'openid-client';

import { AuthController } from './auth.controller';
import { AuthenticatedGuard } from './authenticated.guard';
import {
  OIDC_CLIENT,
  OIDC_CONFIG,
  OIDC_STRATEGY,
  loadOidcConfig,
  type OidcConfig,
} from './oidc.config';
import { OidcAuthGuard } from './oidc-auth.guard';
import { OidcStrategy } from './oidc.strategy';
import { SessionSerializer } from './session.serializer';

const logger = new Logger('AuthModule');

const oidcConfigProvider: Provider = {
  provide: OIDC_CONFIG,
  inject: [ConfigService],
  useFactory: (config: ConfigService) => loadOidcConfig(config),
};

/**
 * Reads the tenant's discovery document once at start-up (endpoints, JWKS URI,
 * supported algorithms) and builds a confidential client from it.
 */
const oidcClientProvider: Provider = {
  provide: OIDC_CLIENT,
  inject: [OIDC_CONFIG],
  useFactory: async (oidc: OidcConfig | null): Promise<Client | null> => {
    if (!oidc) {
      return null;
    }

    const issuer = await Issuer.discover(oidc.discoveryUrl);
    logger.log(`Discovered Azure AD B2C issuer ${issuer.issuer}`);

    return new issuer.Client({
      client_id: oidc.clientId,
      client_secret: oidc.clientSecret,
      redirect_uris: [oidc.redirectUri],
      post_logout_redirect_uris: [oidc.postLogoutRedirectUri],
      response_types: ['code'],
      token_endpoint_auth_method: 'client_secret_post',
    });
  },
};

/**
 * Instantiating the strategy registers it with Passport under the name `oidc`.
 * It is a factory because the client it needs is only known after discovery.
 */
const oidcStrategyProvider: Provider = {
  provide: OIDC_STRATEGY,
  inject: [OIDC_CLIENT, OIDC_CONFIG],
  useFactory: (client: Client | null, oidc: OidcConfig | null) =>
    client && oidc ? new OidcStrategy(client, oidc) : null,
};

@Module({
  imports: [ConfigModule, PassportModule.register({ session: true })],
  controllers: [AuthController],
  providers: [
    oidcConfigProvider,
    oidcClientProvider,
    oidcStrategyProvider,
    SessionSerializer,
    OidcAuthGuard,
    AuthenticatedGuard,
  ],
  exports: [OIDC_CONFIG, AuthenticatedGuard],
})
export class AuthModule {}
