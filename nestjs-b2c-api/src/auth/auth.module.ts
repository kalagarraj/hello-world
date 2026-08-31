import { Logger, Module, Provider } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { PassportModule } from '@nestjs/passport';
import { Issuer } from 'openid-client';

import {
  B2C_CONFIG,
  B2C_ISSUER,
  JWT_STRATEGY,
  loadB2cApiConfig,
  type B2cApiConfig,
  type B2cIssuerMetadata,
} from './b2c.config';
import { JwtAuthGuard } from './jwt-auth.guard';
import { JwtStrategy } from './jwt.strategy';

const logger = new Logger('AuthModule');

const b2cConfigProvider: Provider = {
  provide: B2C_CONFIG,
  inject: [ConfigService],
  useFactory: (config: ConfigService) => loadB2cApiConfig(config),
};

/**
 * Reads the tenant's discovery document once at startup for the issuer and the
 * JWKS URI, so neither is hard-coded and a misconfigured tenant fails the
 * deploy rather than every request.
 */
const b2cIssuerProvider: Provider = {
  provide: B2C_ISSUER,
  inject: [B2C_CONFIG],
  useFactory: async (b2c: B2cApiConfig): Promise<B2cIssuerMetadata> => {
    const issuer = await Issuer.discover(b2c.discoveryUrl);
    const jwksUri = issuer.metadata.jwks_uri;

    if (!jwksUri) {
      throw new Error(
        `Discovery document at ${b2c.discoveryUrl} has no jwks_uri, so tokens cannot be validated`,
      );
    }

    logger.log(`Validating tokens from ${issuer.metadata.issuer}`);
    return { issuer: issuer.metadata.issuer, jwksUri };
  },
};

/** Instantiating the strategy registers it with Passport under the name `jwt`. */
const jwtStrategyProvider: Provider = {
  provide: JWT_STRATEGY,
  inject: [B2C_CONFIG, B2C_ISSUER],
  useFactory: (b2c: B2cApiConfig, issuerMetadata: B2cIssuerMetadata) =>
    new JwtStrategy(b2c, issuerMetadata),
};

@Module({
  imports: [ConfigModule, PassportModule],
  providers: [
    b2cConfigProvider,
    b2cIssuerProvider,
    jwtStrategyProvider,
    JwtAuthGuard,
  ],
  exports: [JwtAuthGuard, B2C_CONFIG],
})
export class AuthModule {}
