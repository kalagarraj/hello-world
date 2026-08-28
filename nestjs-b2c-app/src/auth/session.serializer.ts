import { Injectable } from '@nestjs/common';
import { PassportSerializer } from '@nestjs/passport';

import type { AppUser } from './user.model';

/**
 * The user object is small (ID token claims only), so it is stored directly in
 * the session store rather than being looked up again on every request.
 */
@Injectable()
export class SessionSerializer extends PassportSerializer {
  serializeUser(user: AppUser, done: (err: Error | null, user: AppUser) => void) {
    done(null, user);
  }

  deserializeUser(
    payload: AppUser,
    done: (err: Error | null, user: AppUser) => void,
  ) {
    done(null, payload);
  }
}
