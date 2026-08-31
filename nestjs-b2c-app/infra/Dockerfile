# syntax=docker/dockerfile:1

# ---- build: compile TypeScript with dev dependencies present ----------------
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json tsconfig.build.json nest-cli.json ./
COPY src ./src
RUN npm run build

# ---- deps: production dependency tree only ---------------------------------
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# ---- runtime ---------------------------------------------------------------
FROM node:22-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
# main.js resolves views and static assets as ../views and ../public relative to
# dist/, so these must sit beside dist rather than inside it.
COPY views ./views
COPY public ./public
COPY package.json ./

# node:alpine ships an unprivileged `node` user; nothing here needs root.
USER node

EXPOSE 3000

# Uses the app's own /healthz endpoint. Node 22 has global fetch, so this needs
# no curl or wget in the image.
HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "dist/main.js"]
