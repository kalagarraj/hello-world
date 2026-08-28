# NestJS Hello World with Azure AD B2C

A minimal NestJS app that authenticates users against an **Azure AD B2C** user
flow using the OpenID Connect **authorization code flow with PKCE**.

* Home page (`/`) is public and has a **Log in with Azure AD B2C** button.
* After signing in, B2C redirects back to `/auth/callback` and the user lands on
  `/welcome`, which shows the profile details from their ID token.
* `/auth/logout` clears the local session and ends the B2C session too.

## No MSAL

Authentication is handled by [`openid-client`](https://github.com/panva/openid-client)
— a generic, certified OpenID Connect client — wired into NestJS through
`@nestjs/passport`. There is no dependency on `@azure/msal-node`,
`@azure/msal-browser` or `passport-azure-ad`.

| Concern | Library |
| --- | --- |
| OIDC discovery, PKCE, code exchange, ID token validation | `openid-client` |
| Strategy/guard plumbing | `passport`, `@nestjs/passport` |
| Session cookie | `express-session` |
| Views | `hbs` |

## Getting started

```bash
cd nestjs-b2c-app
npm install
cp .env.example .env    # then fill in your tenant values
npm run start:dev
```

Open <http://localhost:3000>. Without a filled-in `.env` the app still boots and
shows a setup page instead of the login button.

## Azure AD B2C configuration

1. In your B2C tenant, create a sign-up/sign-in **user flow**, e.g.
   `B2C_1_signupsignin`.
2. Create an **App registration** of type *Web*:
   * Redirect URI: `http://localhost:3000/auth/callback`
   * Front-channel logout / post logout redirect URI: `http://localhost:3000/`
   * Implicit grant is **not** needed — this app uses the code flow.
3. Under *Certificates & secrets*, create a **client secret**.
4. Fill in `.env`:

   | Variable | Example |
   | --- | --- |
   | `B2C_TENANT_NAME` | `contoso` (for `contoso.onmicrosoft.com`) |
   | `B2C_POLICY_NAME` | `B2C_1_signupsignin` |
   | `B2C_CLIENT_ID` | application (client) ID |
   | `B2C_CLIENT_SECRET` | client secret value |
   | `B2C_REDIRECT_URI` | `http://localhost:3000/auth/callback` |
   | `B2C_POST_LOGOUT_REDIRECT_URI` | `http://localhost:3000/` |
   | `SESSION_SECRET` | `openssl rand -base64 32` |

### Confidential vs public client

By default the app runs as a **confidential client**: it sends `B2C_CLIENT_SECRET`
to the token endpoint. That is the right shape for a server-rendered app, since
the secret never leaves the server.

It only works if B2C considers the registration confidential. If the redirect URI
is registered under **Mobile and desktop applications**, or **Allow public client
flows** is set to *Yes*, B2C classifies the app as public and rejects the secret:

```
AADB2C90084: Public clients should not send a client_secret when redeeming
a publicly acquired grant.
```

Two ways out:

* **Preferred** — make the registration confidential: in *Authentication*, register
  `http://localhost:3000/auth/callback` under the **Web** platform (remove it from
  *Mobile and desktop applications*) and set *Allow public client flows* to **No**.
* **Or** leave `B2C_CLIENT_SECRET` empty. The app then configures a public client
  with `token_endpoint_auth_method: 'none'` and relies on PKCE alone. Startup logs
  which mode is in effect.

The discovery document is derived as
`https://<tenant>.b2clogin.com/<tenant>.onmicrosoft.com/<policy>/v2.0/.well-known/openid-configuration`.
Set `B2C_DISCOVERY_URL` explicitly for custom domains, custom policies, or
`*.ciamlogin.com` tenants.

## Watching the flow

Every step of the sign-in and authorization flow is traced to the console under
the `AuthFlow` context. A full login, one protected page view and a sign-out
look like this:

```
[AuthFlow] AUTHZ DENY          flow=SijW5m0w route=GET /welcome reason=no authenticated session redirect=/?error=signin_required
[AuthFlow] 1. LOGIN START      flow=PaBS-zyh endpoint=https://.../authorize scope=openid profile email offline_access
[AuthFlow] 1b. PKCE GENERATED  flow=PaBS-zyh code_verifier=kept in session (43 chars) code_challenge=nFiZDblKQO_guTGUhDB1Di95sPfJh_3ijAxLPSCJXVk code_challenge_method=S256 state=sent
[AuthFlow] 2. CALLBACK         flow=PaBS-zyh code=received state=matches sent value
[AuthFlow] 3. TOKEN EXCHANGE   flow=PaBS-zyh endpoint=https://.../token auth_method=client_secret_post code_verifier=replayed (43 chars, proves same client)
[AuthFlow] 4. TOKENS RECEIVED  flow=PaBS-zyh id_token=yes(909 chars) access_token=yes(17 chars) refresh_token=yes(12 chars) expires_in=3600
[AuthFlow] 5. ID TOKEN VALID   flow=PaBS-zyh iss=... aud=... sub=... claims=[oid, name, given_name, family_name, emails, idp, tfp, ...]
[AuthFlow] 6. USER MAPPED      flow=PaBS-zyh name=Ada Lovelace email=ada@example.com idp=google.com policy=B2C_1_signupsignin
[AuthFlow] 7. SESSION WRITE    user=Ada Lovelace id=99999999-...
[AuthFlow] 8. LOGIN COMPLETE   flow=PaBS-zyh -> ct0lAp5S session=regenerated (fixation defence) authenticated=true next=/welcome
[AuthFlow] SESSION READ        user=Ada Lovelace
[AuthFlow] AUTHZ ALLOW         flow=ct0lAp5S route=GET /welcome user=Ada Lovelace
[AuthFlow] 9. LOGOUT START     flow=ct0lAp5S user=Ada Lovelace
[AuthFlow] 10. SESSION CLEARED flow=ct0lAp5S cookie=b2c.sid removed
[AuthFlow] 11. B2C SIGN-OUT    flow=ct0lAp5S endpoint=https://.../logout id_token_hint=sent post_logout_redirect_uri=http://localhost:3000/
```

Reading it:

* **Steps 1-8 are authentication** (proving who the user is), and the
  `AUTHZ ALLOW` / `AUTHZ DENY` lines are **authorization** (deciding whether this
  request may proceed). `SESSION READ` appears once per request, where the
  session cookie is turned back into a user.
* `flow=` correlates the legs of one sign-in. It is derived from the session id,
  which Passport regenerates at login to defeat session fixation — step 8 prints
  both halves so the chain stays followable.
* **PKCE is shown end to end.** Step 1b prints the `code_challenge` actually
  sent to B2C — the SHA-256 hash of a one-time verifier — and step 3 shows that
  verifier being replayed at the token endpoint. That pairing is what proves the
  code is being redeemed by the same client that requested it, so an intercepted
  authorization code is useless on its own. The verifier is the secret half and
  never leaves the session, so only its length is logged. Where PKCE is in play
  openid-client omits the nonce, and the trace says so rather than leaving a
  silent gap.
* Nothing secret is printed. Authorization codes, PKCE verifiers, the client
  secret and the tokens themselves are reported as presence and length only.
  Claim *values* are logged, since the welcome page displays them anyway; drop
  step 6 if that is too much for your environment.

Set `AUTH_TRACE=false` to turn the whole trace off.

## Routes

| Route | Description |
| --- | --- |
| `GET /` | Public home page with the login button |
| `GET /auth/login` | Redirects to the B2C authorize endpoint |
| `GET /auth/callback` | Code exchange + session creation, then redirects to `/welcome` |
| `GET /welcome` | Protected — shows the signed-in user's details |
| `GET /auth/logout` | Local sign-out, then B2C `end_session_endpoint` |
| `GET /setup` | Setup instructions shown when B2C is not configured |
| `GET /healthz` | Liveness probe |

## How it fits together

```
src/
  main.ts                    bootstrap, hbs views, session middleware, passport
  session/
    session.config.ts        APP_ENV / REDIS_URL -> session settings
    session.factory.ts       picks in-process or Redis store, fails fast
  auth/
    oidc.config.ts           env -> OidcConfig (discovery URL, client, scopes)
    auth.module.ts           discovery at startup -> Client -> Strategy providers
    oidc.strategy.ts         openid-client Passport strategy (code flow + PKCE)
    oidc-auth.guard.ts       starts the redirect, logs the user in on callback
    authenticated.guard.ts   protects /welcome
    session.serializer.ts    stores the user in the session
    user.model.ts            maps B2C claims (oid, emails[], tfp, idp) to AppUser
  home/
    home.controller.ts       /, /welcome, /setup, /healthz
views/                       handlebars templates
public/styles.css            styling
```

Claim mapping worth knowing about: B2C returns e-mail addresses in an `emails`
array (not the standard `email` claim), the account identifier in `oid`, and the
user flow name in `tfp` — `user.model.ts` normalises all three.

## Session storage per environment

`APP_ENV` selects the store, so no code changes between local and Azure:

| `APP_ENV` | `REDIS_URL` | Store | Behaviour |
| --- | --- | --- | --- |
| `local` | unset | in-process | No infrastructure needed |
| `dev` / `test` / `prod` | set | Azure Cache for Redis | Survives restarts, shared across instances |
| anything but `local` | unset | — | **Startup fails** |

That last row is deliberate. The in-process store silently loses every session on
restart and gives each instance its own view of who is signed in, which surfaces
in production as users being randomly signed out. Failing the deploy is better
than shipping that. `SESSION_ALLOW_MEMORY_STORE=true` overrides it for a
throwaway environment, and logs a warning every boot.

### Pointing an Azure environment at Redis

Get the connection string from the portal: your Redis resource -> **Access keys**
-> *Primary connection string*. Azure requires TLS, so the URL is `rediss://` on
port 6380:

```
REDIS_URL=rediss://:<access-key>@<name>.redis.cache.windows.net:6380
```

Set it as an app setting on the App Service / Container App for each environment
(deployment slots carry their own settings, so a staging slot can point at its
own cache). The client connects during bootstrap, so a wrong URL or a missing
firewall rule fails the deploy rather than every user's sign-in.

### Several Azure environments

Each environment writes under its own key prefix, defaulting to
`sess:<APP_ENV>:`, so dev, test and prod can share one cache without colliding —
a session issued by dev is simply not found by test.

**Prefixes are namespacing, not a security boundary.** Anyone holding the access
key can read every prefix in that cache. For environments at different trust
levels — prod especially — give each its own cache instance, or at minimum its
own Redis database and key. Sharing is fine between dev and test; prod should be
alone.

Two other things worth knowing: the Basic tier is a single node with no SLA, so
maintenance signs everybody out — use Standard or above where that matters. And
sessions carry a TTL derived from `SESSION_MAX_AGE_MS`, so abandoned sessions
expire rather than accumulating.

## Notes for production

* Keep `SESSION_SECRET` and `B2C_CLIENT_SECRET` in a secret store (Key Vault
  referenced from app settings), not in the repo.
* `SESSION_SECRET` must be identical across every instance of one environment,
  or instances cannot read each other's cookies — and different between
  environments.
* The app trusts one proxy hop (`trust proxy`), which is what Azure's front end
  needs for the `secure` cookie flag to behave.
