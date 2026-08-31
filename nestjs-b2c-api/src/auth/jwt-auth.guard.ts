import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

/** Rejects any request without a valid B2C bearer token. */
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {}
