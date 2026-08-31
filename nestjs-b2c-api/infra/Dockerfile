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
COPY package.json ./

USER node

EXPOSE 3001

# The API has exactly one route and it requires a token, so liveness is probed
# by asserting that an unauthenticated call is *rejected*. A 401 proves both
# that the process is serving and that the guard is wired; a 200 here would
# mean authentication had been bypassed, and is treated as unhealthy.
HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3001/hello').then(r=>process.exit(r.status===401?0:1)).catch(()=>process.exit(1))"

CMD ["node", "dist/main.js"]
