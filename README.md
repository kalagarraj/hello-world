# Hello React (minimal)

This is a minimal "Hello, React!" app implemented as a single static `index.html` that loads React and ReactDOM from a CDN. No build step or Node.js is required to run it.

How to run

- Open `index.html` in your browser (double-click or use the browser "Open File" option).
- Or serve it from a simple static server, e.g. with Python 3:

```bash
python3 -m http.server 3000
# then open http://localhost:3000 in your browser
```

What you'll see

- A page with "Hello, React!" and a button that triggers an alert when clicked.

Notes

- This setup is suitable for demos and learning. For a real project, consider creating a full React app using Vite, Create React App, or similar tooling.
# hello-world

## Also in this repo

- [`nestjs-b2c-api/`](nestjs-b2c-api/) — a companion NestJS API whose single
  `GET /hello` endpoint accepts the Azure AD B2C bearer tokens issued to the app
  below, validating them against the tenant's JWKS.
- [`nestjs-b2c-app/`](nestjs-b2c-app/) — a NestJS "Hello World" that signs users
  in against an Azure AD B2C user flow over OpenID Connect (via `openid-client`,
  not MSAL), with a public home page and a protected welcome page showing the
  user's details.
