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

| Check | Rejected with |
| --- | --- |
| Signature against the tenant's JWKS (RS256) | `401` |
| `iss` matches the discovered issuer | `401` |
| `aud` matches `B2C_API_AUDIENCE` | `401` |
| `exp` in the future (no skew allowance) | `401` |
| `scp` contains `B2C_REQUIRED_SCOPE`, when set | `403` |

The audience check is what stops a token minted for a *different* API from
being replayed here, so `B2C_API_AUDIENCE` must be this API's own app
registration, not the web app's. The scope failure is deliberately `403` rather
than `401`: the caller proved who they are, they are simply not allowed here.

Signing keys are fetched from the discovered `jwks_uri` and cached for ten
minutes, so a key rotation is picked up without a restart. Requests for unknown
key IDs are rate limited, so a bad token cannot be used to hammer the tenant.

## Azure AD B2C setup

This needs **two** app registrations — the web app that signs users in, and
this API. If you only have the first, B2C will not issue a token this API can
accept.

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

Without step 4 the web app receives a token that is not addressed to this API,
and every call returns `401` — which is correct behaviour, not a bug.

## Running it

```bash
npm install
cp .env.example .env    # fill in tenant, policy and B2C_API_AUDIENCE
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
