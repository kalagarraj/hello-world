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
infra/
  Dockerfile                 multi-stage build for the app image
  docker-compose.yml         app + Redis (project b2c-local)
  docker-compose.cosmos.yml  Cosmos DB emulator (project b2c-cosmos)
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

### Running the app itself in a container

`infra/Dockerfile` builds the app; `npm run docker:up` builds it and starts it
alongside Redis:

```bash
npm run docker:up      # build + start app and redis
npm run docker:logs    # follow the app
npm run docker:down    # stop both
```

The app is then on http://localhost:3000 exactly as before, so the B2C redirect
URIs registered for local development keep working -- the browser still talks to
`localhost:3000`, only the process moved.

Worth knowing about the setup:

* **Multi-stage build.** TypeScript is compiled in one stage with dev
  dependencies, production dependencies are installed in another, and the
  runtime image takes only `dist`, `views`, `public` and the production
  `node_modules`. No compiler or test tooling ships in the final image.
* `views` and `public` sit *beside* `dist`, not inside it, because `main.js`
  resolves them as `../views` and `../public`. Getting that wrong produces an
  app that boots cleanly and then 500s on the first page render.
* **`REDIS_URL` is overridden to `redis://redis:6379`** in the Compose file.
  Inside the network Redis answers to its service name; `localhost` would be the
  app's own container. Everything else comes from your `.env` through
  `env_file`.
* `.env` is in `.dockerignore`, so secrets are **not** baked into the image --
  they are supplied at runtime.
* The container runs as the unprivileged `node` user, and `init: true` forwards
  signals so `docker stop` reaches Node's shutdown handlers.
* The healthcheck calls the app's own `/healthz` using Node's global `fetch`, so
  the image needs no `curl` or `wget`.
* Compose waits for Redis to report healthy before starting the app, since the
  app fails fast when Redis is unreachable.
* No service sets `container_name`. That name is global across every Compose
  project on the machine, so a leftover container from a different project name
  blocks startup with *"the container name is already in use"*. Compose derives
  names like `b2c-local-redis-1` instead, scoped to this project.

If you ran an earlier revision of this repo, containers from the old project
name may still be holding those names. Clear them once:

```bash
docker rm -f b2c-redis b2c-app b2c-cosmos 2>/dev/null || true
```

The old `nestjs-b2c-app_redis-data` volume is likewise orphaned by the project
rename; `docker volume rm nestjs-b2c-app_redis-data` if you want it gone. Both
only cost you the local sessions stored in them.

### Running Redis locally in Docker

Optional -- local development works with no container at all, since an unset
`REDIS_URL` keeps sessions in process. Use the container when you want to
exercise the same store the deployed environments use, or to keep sessions
across app restarts.

```bash
npm run redis:up          # docker compose -f infra/docker-compose.yml up -d redis
```

Then set `REDIS_URL=redis://localhost:6379` in `.env` and start the app. It logs
which store it picked at boot:

```
[SessionStore] Connected to Redis for local sessions
[SessionStore] env=local store=redis prefix=sess:local: secure_cookie=false
```

| Script | Does |
| --- | --- |
| `npm run redis:up` | Start Redis in the background |
| `npm run redis:down` | Stop it, keeping the data volume |
| `npm run redis:reset` | Stop it and delete every session |
| `npm run redis:cli` | Open `redis-cli` inside the container |
| `npm run redis:sessions` | List the session keys currently stored |
| `npm run redis:logs` | Tail the container logs |

Two deliberate choices in `infra/docker-compose.yml`: the port is published to
`127.0.0.1` only, because an unauthenticated Redis reachable from the network
would let anyone on it read and forge session cookies; and append-only
persistence is on, so `docker compose restart` keeps sessions the way Azure does
when the app restarts.

The image is `redis:8-alpine`. Redis 8 absorbed Redis Stack, so JSON, the query
engine, time series and the probabilistic types are part of core -- there is no
reason to reach for `redis/redis-stack-server`, whose maintenance releases ended
in December 2025 and which is roughly seven times the download. Sessions use
none of that either way: `connect-redis` only issues `SET`, `GET`, `DEL`,
`EXPIRE` and `TTL`, which behave identically on the older Redis versions the
Azure tiers run, so the local/Azure version gap does not affect this app.

The local URL is `redis://` (plaintext) while Azure is `rediss://` (TLS). That
difference is carried entirely by the URL scheme -- no code or config branch.

If `REDIS_URL` is set and Redis is not reachable, startup fails within a few
seconds and names the fix rather than retrying forever:

```
Could not connect to Redis at redis://localhost:6379 - could not reach Redis
after 5 attempts. Is the local container running? Start it with `npm run redis:up`.
```

### Azure Cosmos DB emulator (optional)

The emulator lives in its own file, `infra/docker-compose.cosmos.yml`, separate from
the Redis stack -- nothing in this app uses Cosmos, and the emulator is far
heavier than Redis, so it should not share a lifecycle with it.

```bash
npm run cosmos:up      # docker compose -f infra/docker-compose.cosmos.yml up -d
npm run cosmos:logs    # follow startup, which takes a while on first run
npm run cosmos:down    # stop and remove it
```

The file declares its own Compose project name (`b2c-cosmos`). Both files
otherwise inherit the project name from the directory, and Compose would then
treat each stack's containers as orphans of the other -- `docker compose down`
on Redis would warn about the emulator, and vice versa. Separate names keep
`npm run redis:down` and `npm run cosmos:down` fully independent.

| What | Where |
| --- | --- |
| Gateway / data plane | `http://localhost:8081` |
| Data Explorer | `http://localhost:1234` |

The account key is the fixed, publicly documented emulator key -- the same
string for every install, and deliberately not a secret:

```
C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==
```

Never let that value near a real deployment: anything holding it is talking to
an emulator, and a config that accepts it in a deployed environment is a bug.

Notes on the setup:

* It runs with `--protocol http`, which is the emulator's default. HTTPS
  generates a self-signed certificate every client must then trust.
  **The .NET and Java SDKs require HTTPS** -- if you use either, switch the
  command to `['--protocol', 'https']` and publish port 8080 as well. With the
  `/data` volume attached the emulator regenerates its certificate at startup,
  so persistence and HTTPS work together.
* Data persists in a `cosmos-data` volume mounted at `/data`, so databases and
  containers survive a restart. `npm run cosmos:down` removes the container but
  keeps the volume; add `-v` to wipe it.
* To seed on first start, mount a directory of `cosmoshell` commands at `/init`
  and set `ENABLE_INIT_DATA=true` -- both are stubbed as comments in the file.
* Like Redis, the ports publish to `127.0.0.1` only.
* This is the `vnext` Linux emulator, which runs natively on Apple silicon and
  ARM as well as x86, unlike the older emulator image.
* It serves the **NoSQL API**. If you need the MongoDB or Cassandra API, check
  current support before relying on this image.

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
