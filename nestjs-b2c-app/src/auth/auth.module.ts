import { Logger, Module, Provider } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { PassportModule } from '@nestjs/passport';
import { Client, Issuer } from 'openid-client';

import { AuthController } from './auth.controller';
import { AuthenticatedGuard } from './authenticated.guard';
import {
  OIDC_CLIENT,
  OIDC_CONFIG,
  OIDC_INSPECTION,
  OIDC_STATUS,
  OIDC_STRATEGY,
  inspectOidcConfig,
  type OidcConfig,
  type OidcStatus,
} from './oidc.config';
import { OidcAuthGuard } from './oidc-auth.guard';
import { OidcStrategy } from './oidc.strategy';
import { SessionSerializer } from './session.serializer';

const logger = new Logger('AuthModule');

type OidcInspection = ReturnType<typeof inspectOidcConfig>;

/** Read the environment once; OIDC_CONFIG and OIDC_STATUS both derive from it. */
const oidcInspectionProvider: Provider = {
  provide: OIDC_INSPECTION,
  inject: [ConfigService],
  useFactory: (config: ConfigService) => inspectOidcConfig(config),
};

const oidcConfigProvider: Provider = {
  provide: OIDC_CONFIG,
  inject: [OIDC_INSPECTION],
  useFactory: (inspection: OidcInspection): OidcConfig | null =>
    inspection.config,
};

const oidcStatusProvider: Provider = {
  provide: OIDC_STATUS,
  inject: [OIDC_INSPECTION],
  useFactory: (inspection: OidcInspection): OidcStatus => inspection.status,
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

    // A registration B2C treats as public rejects a secret at the token
    // endpoint (AADB2C90084), so authenticate with `none` and let PKCE carry
    // the proof. With a secret present the client stays confidential.
    const isConfidential = Boolean(oidc.clientSecret);
    logger.log(
      `Using a ${isConfidential ? 'confidential' : 'public'} client for ${oidc.clientId}`,
    );

    return new issuer.Client({
      client_id: oidc.clientId,
      ...(isConfidential ? { client_secret: oidc.clientSecret } : {}),
      redirect_uris: [oidc.redirectUri],
      post_logout_redirect_uris: [oidc.postLogoutRedirectUri],
      response_types: ['code'],
      token_endpoint_auth_method: isConfidential ? 'client_secret_post' : 'none',
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
    oidcInspectionProvider,
    oidcConfigProvider,
    oidcStatusProvider,
    oidcClientProvider,
    oidcStrategyProvider,
    SessionSerializer,
    OidcAuthGuard,
    AuthenticatedGuard,
  ],
  exports: [OIDC_CONFIG, OIDC_STATUS, AuthenticatedGuard],
})
export class AuthModule {}
