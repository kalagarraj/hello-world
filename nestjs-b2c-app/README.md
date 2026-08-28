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
  main.ts                    bootstrap, hbs views, express-session, passport
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

## Notes for production

* Set `NODE_ENV=production` so the session cookie is issued with `secure`.
* Replace the in-memory session store (`express-session`'s default) with Redis or
  another shared store before running more than one instance.
* Keep `SESSION_SECRET` and `B2C_CLIENT_SECRET` in a secret store, not in the repo.
