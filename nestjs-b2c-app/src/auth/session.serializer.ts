import { Injectable } from '@nestjs/common';
import { PassportSerializer } from '@nestjs/passport';

import { authFlow } from './auth-flow.logger';
import type { AppUser } from './user.model';

/**
 * The user object is small (ID token claims only), so it is stored directly in
 * the session store rather than being looked up again on every request.
 */
@Injectable()
export class SessionSerializer extends PassportSerializer {
  serializeUser(user: AppUser, done: (err: Error | null, user: AppUser) => void) {
    authFlow('7. SESSION WRITE', { user: user.name, id: user.id });
    done(null, user);
  }

  deserializeUser(
    payload: AppUser,
    done: (err: Error | null, user: AppUser) => void,
  ) {
    authFlow('SESSION READ', { user: payload?.name });
    done(null, payload);
  }
}
