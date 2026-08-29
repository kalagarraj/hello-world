# Running the stack on a local Kubernetes cluster, one piece at a time

The same containers the Compose files run, scheduled by Kubernetes on your own
machine. Each step below deploys **one** component and ends with a check that
either passes or tells you exactly what is wrong — so when something breaks you
know which piece broke, instead of staring at six pods that all came up at once.

Every step applies the same overlay, filtered by label:

```bash
kubectl apply -k k8s/local -l app.kubernetes.io/component=<component>
```

| component | creates | step |
| --- | --- | --- |
| `config` | Namespace, `b2c-config` ConfigMap | 1 |
| `cache` | Redis Deployment + Service | 3 |
| `api` | API Deployment + Service | 4 |
| `web` | web Deployment + Service | 5 |
| `metrics` | Prometheus config, Deployment + Service | 6 |
| `dashboard` | Grafana provisioning, dashboard, Deployment + Service | 7 |

Nothing is applied twice by accident: re-running a step is idempotent, and step 8
applies the whole overlay unfiltered, which by then changes nothing.

## Step 0 — a cluster to deploy into

You need Docker, `kubectl`, and a single-node cluster. Any of these work:

```bash
# kind (used to verify this walkthrough)
kind create cluster --name b2c

# ...or minikube
minikube start

# ...or tick "Enable Kubernetes" in Docker Desktop's settings
```

```bash
kubectl cluster-info          # the control plane answers
kubectl get nodes             # one node, STATUS Ready
```

If `kubectl` talks to the wrong cluster later, `kubectl config current-context`
is the thing to check first — every command below acts on the current context.

## Step 1 — namespace and configuration

The non-secret values live in `k8s/base/config.yaml`, which ships with
placeholders. Put your tenant and client ID there (one place, all environments),
or override just this cluster by uncommenting the `configMapGenerator` block in
`k8s/local/kustomization.yaml`.

```bash
kubectl apply -k k8s/local -l app.kubernetes.io/component=config
# namespace/b2c created
# configmap/b2c-config created
```

Two objects, not fifteen — that is the label filter doing its job. Let the
overlay create the namespace rather than `kubectl create namespace`: a namespace
created imperatively and then applied over draws a warning about the missing
`last-applied-configuration` annotation.

**Check**

```bash
kubectl -n b2c get configmap b2c-config -o jsonpath='{.data}' ; echo
```

The tenant name it prints is the one the web app will call at start-up. If it
still says `contoso`, step 5 will crash-loop — that failure is described there.

## Step 2 — secrets

Secrets are created by hand and never committed. `k8s/base/secret.example.yaml`
is a template that the kustomization deliberately does not apply.

```bash
kubectl -n b2c create secret generic b2c-secrets \
  --from-literal=SESSION_SECRET="$(openssl rand -base64 32)" \
  --from-literal=B2C_CLIENT_SECRET=''
```

An empty `B2C_CLIENT_SECRET` runs the app as a **public client** — PKCE only, no
secret at the token endpoint. That matches the default local `.env`, and it is
what a B2C registration created under the "Single-page application" or "Mobile
and desktop" platform requires. If your registration is a confidential Web
client, put its secret in instead.

Both pods mount this Secret with `envFrom`, so it has to exist before step 4 —
without it the pods stay in `CreateContainerConfigError`.

**Check**

```bash
kubectl -n b2c get secret b2c-secrets
# NAME          TYPE     DATA   AGE
# b2c-secrets   Opaque   2      3s
```

## Step 3 — Redis

Sessions live in Redis rather than in the web pod, which is what lets the
Deployment scale past one replica without signing people out.

```bash
kubectl apply -k k8s/local -l app.kubernetes.io/component=cache
kubectl -n b2c rollout status deploy/redis
```

**Check**

```bash
kubectl -n b2c exec deploy/redis -- redis-cli ping
# PONG
```

## Step 4 — the API

Build the image and put it where the cluster's container runtime can see it.
This is the part that has no equivalent in Compose: your local Docker daemon and
the cluster's runtime are two different image stores.

```bash
docker build -t b2c-api:local -f nestjs-b2c-api/infra/Dockerfile nestjs-b2c-api

kind load docker-image b2c-api:local --name b2c   # kind
# minikube image load b2c-api:local               # minikube
# k3d image import b2c-api:local -c b2c           # k3d
# Docker Desktop shares its daemon with the cluster — nothing to load
```

```bash
kubectl apply -k k8s/local -l app.kubernetes.io/component=api
kubectl -n b2c rollout status deploy/api
```

**Check** — in one terminal:

```bash
kubectl -n b2c port-forward svc/api 3001:3001 9464:9464
```

and in another:

```bash
curl -i http://localhost:3001/hello        # HTTP/1.1 401 Unauthorized  <- correct
curl -s http://localhost:9464/metrics | grep api_requests_total | head -3
```

A 401 is the success case: the endpoint requires a bearer token and there is no
token on that request. The metrics port answers unauthenticated, which is why
the pod's readiness probe points at it — probing `/hello` would read 401 as
unhealthy and restart a perfectly good pod.

## Step 5 — the web app

```bash
docker build -t b2c-web:local -f nestjs-b2c-app/infra/Dockerfile nestjs-b2c-app
kind load docker-image b2c-web:local --name b2c

kubectl apply -k k8s/local -l app.kubernetes.io/component=web
kubectl -n b2c rollout status deploy/web
```

**Check**

```bash
kubectl -n b2c port-forward svc/web 3000:3000
```

Open <http://localhost:3000>: the home page with its **Sign in** button, plus
the anonymous API-demo link that shows the API rejecting an unauthenticated
call. Sign in, and the welcome page shows your claims and the authorized call
against the API pod. The session is now in Redis, not in the pod:

```bash
kubectl -n b2c exec deploy/redis -- redis-cli KEYS 'sess:dev:*'
```

Port 3000 is not cosmetic: `APP_BASE_URL` is `http://localhost:3000`, so the
redirect URI the app sends to B2C is `http://localhost:3000/auth/callback` —
the one already registered for local development. Forward a different port and
B2C will refuse the request.

**If the pod crash-loops.** The web app reads the B2C discovery document at
start-up and exits if it cannot:

```bash
kubectl -n b2c logs deploy/web --previous | tail -20
# getaddrinfo ENOTFOUND contoso.b2clogin.com
```

That is step 2 with placeholder values still in it. Fix the ConfigMap, re-apply
the `config` component, then `kubectl -n b2c rollout restart deploy/web`.

## Step 6 — Prometheus

```bash
kubectl apply -k k8s/local -l app.kubernetes.io/component=metrics
kubectl -n b2c rollout status deploy/prometheus
```

**Check**

```bash
kubectl -n b2c port-forward svc/prometheus 9090:9090
curl -s 'http://localhost:9090/api/v1/targets?state=active' \
  | grep -o '"health":"[a-z]*"'
# "health":"up"
```

Prometheus scrapes `api:9464` — the Service, not a pod IP — so it keeps working
when the API is rescheduled or scaled.

## Step 7 — Grafana

```bash
kubectl apply -k k8s/local -l app.kubernetes.io/component=dashboard
kubectl -n b2c rollout status deploy/grafana
```

**Check**

```bash
kubectl -n b2c port-forward svc/grafana 3300:3000
```

Open <http://localhost:3300/dashboards> → **B2C → API calls**. Anonymous viewer
access is on, so there is no login. Port 3300 only to keep 3000 free for the web
app; nothing in Grafana depends on it.

Panels are empty until the API has served something. Generate a little traffic —
the two demo links on the home and welcome pages, or a handful of `curl`s
against the forwarded API port — and the rejection panels fill in from the 401s.

## Step 8 — the whole thing in one command

Once each piece has been proven, the unfiltered apply is how you would deploy it
day to day:

```bash
kubectl apply -k k8s/local
kubectl -n b2c get pods
```

It is the same overlay, so this reports mostly `unchanged`. That is the point:
the step-by-step path and the one-shot path deploy exactly the same objects.

## Changing code and redeploying

```bash
docker build -t b2c-web:local -f nestjs-b2c-app/infra/Dockerfile nestjs-b2c-app
kind load docker-image b2c-web:local --name b2c
kubectl -n b2c rollout restart deploy/web
```

The restart is required. The tag did not change, so nothing in the Deployment
spec changed, and Kubernetes has no reason to replace the pod on its own.

## Tearing down

```bash
kubectl delete -k k8s/local     # the workloads, and the namespace with them
kind delete cluster --name b2c  # or throw the whole cluster away
```

The overlay includes the Namespace, so deleting it takes the Secret you created
by hand along with it. Removing one component is the same filter as applying it:

```bash
kubectl delete -k k8s/local -l app.kubernetes.io/component=dashboard
```

## What this overlay changes, and why

| | base | `k8s/local` |
| --- | --- | --- |
| images | `b2c-web:latest`, pulled | `:local`, `imagePullPolicy: IfNotPresent` |
| replicas | 2 web, 2 api | 1 each |
| `APP_BASE_URL` | overlay's public host | `http://localhost:3000` |
| session cookie | `Secure` | `Secure` off — plain http on localhost drops it |
| Redis | in-cluster (dev) / Azure Cache (prod) | in-cluster |
| Ingress | placeholder host | removed; use `port-forward` |

The Cosmos DB and Snowflake emulators from `infra/` are not here. They exist so
local development can avoid cloud services; running them inside a cluster would
be deploying a fake of the thing standing next to you.
