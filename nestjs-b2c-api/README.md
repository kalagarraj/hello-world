# NestJS API with Azure AD B2C bearer tokens

A minimal resource API with a single endpoint, protected by Azure AD B2C access
tokens issued to a client application — for example the sign-in web app in
[`../nestjs-b2c-app`](../nestjs-b2c-app).

```
GET /hello        Authorization: Bearer <access token>
```

```json
{
  "message": "Hello from the new app",
  "caller": { "subject": "9999...", "name": "Ada Lovelace", "email": "ada@example.com", "scopes": ["api.read"] },
  "tokenIssuedBy": "https://contoso.b2clogin.com/<tenant-id>/v2.0/"
}
```

Anything without a valid token gets `401` before the handler runs.

## No MSAL

Tokens are validated with [`passport-jwt`](https://github.com/mikenicholson/passport-jwt)
and [`jwks-rsa`](https://github.com/auth0/node-jwks-rsa), with
[`openid-client`](https://github.com/panva/openid-client) discovering the
tenant's issuer and JWKS URI. No `@azure/msal-*`, no `passport-azure-ad`.

## What is checked

On every request, before the handler runs:

| Check | Always on | Rejected with |
| --- | --- | --- |
| Signature against the tenant's JWKS (RS256) | yes | `401` |
| `iss` matches the discovered issuer | yes | `401` |
| `exp` in the future (no skew allowance) | yes | `401` |
| `aud` matches `B2C_API_AUDIENCE` | only when set | `401` |
| `scp` contains `B2C_REQUIRED_SCOPE` | only when set | `403` |

By default the audience and scope checks are **off**, so any unexpired token
your tenant signed is accepted — an ID token as readily as an access token.
That is what lets the web app's existing bearer token work with no second app
registration and no extra scope.

**It is also a real weakening**, so be clear-eyed about it: any application in
the tenant can obtain a token this API will accept. There is no privilege
escalation across tenants — a token from a different tenant, a forged one, or an
expired one is still refused — but within the tenant there is no separation. The
API logs a warning on every start while the audience is unset.

Set `B2C_API_AUDIENCE` before deploying anywhere real. When you do, the setup
below applies, and a scope failure answers `403` rather than `401`: the caller
proved who they are, they are simply not allowed here.

Signing keys are fetched from the discovered `jwks_uri` and cached for ten
minutes, so a key rotation is picked up without a restart. Requests for unknown
key IDs are rate limited, so a bad token cannot be used to hammer the tenant.

## Azure AD B2C setup

**Nothing beyond the web app's own setup is required.** Point this API at the
same tenant and user flow, and the token the web app already receives works.

The rest of this section is what to do when you want the audience check on —
recommended before deploying. It needs a second app registration, for the API
itself.

1. Register the API (**App registrations → New registration**).
2. Under **Expose an API**, set the Application ID URI and add a scope, e.g.
   `api.read`. The full scope is then
   `https://<tenant>.onmicrosoft.com/<api-app>/api.read`.
3. In the **web app's** registration, under **API permissions**, add that scope
   and grant admin consent.
4. Add the full scope URI to the web app's `B2C_SCOPE` so B2C issues an access
   token for this API:

   ```
   B2C_SCOPE=openid profile email offline_access https://contoso.onmicrosoft.com/<api-app>/api.read
   ```

5. Here, set `B2C_API_AUDIENCE` to the API registration's Application (client)
   ID, and optionally `B2C_REQUIRED_SCOPE=api.read`.

With `B2C_API_AUDIENCE` set but step 4 skipped, the web app receives a token
that is not addressed to this API and every call returns `401` — correct
behaviour, not a bug.

## Running it

```bash
npm install
cp .env.example .env    # tenant and policy are all that is required
npm run start:dev       # http://localhost:3001
```

Unlike the web app, this one **refuses to start** when it is unconfigured. A web
app with no identity provider can still serve a public page; an API with no way
to validate tokens can only reject everything, or — far worse if someone
"fixes" it hastily — accept everything.

## In Docker

```bash
npm run docker:up      # build and start
npm run docker:logs
npm run docker:down
```

It needs no local infrastructure: validation only requires reaching the tenant's
JWKS endpoint. The image is multi-stage, ships only `dist` and production
dependencies, and runs as the unprivileged `node` user.

The healthcheck asserts that an unauthenticated `GET /hello` returns **401**.
With one route, and that route requiring a token, a 401 proves both that the
process is serving and that the guard is wired — while a 200 would mean
authentication had been bypassed, and is treated as unhealthy.

## Calling it

Take an access token the web app received and:

```bash
curl -H "Authorization: Bearer $TOKEN" http://localhost:3001/hello
```

CORS allows `GET` with an `Authorization` header from `CORS_ORIGIN`
(`http://localhost:3000` by default), so the web app can call it from a browser.

## Layout

```
src/
  main.ts                  bootstrap, CORS
  auth/
    b2c.config.ts          env -> audience, scope, discovery URL
    auth.module.ts         discovery -> issuer + JWKS URI -> strategy
    jwt.strategy.ts        signature / iss / aud / exp, then scope
    jwt-auth.guard.ts      rejects requests without a valid token
  hello/
    hello.controller.ts    GET /hello
infra/
  Dockerfile               multi-stage build
  docker-compose.yml       the API alone (project b2c-api)
```
