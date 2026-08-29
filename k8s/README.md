# Kubernetes manifests

Deploys the web app, the API, Redis, Prometheus and Grafana into a `b2c`
namespace, with Kustomize overlays per environment.

```
k8s/
  base/                 the five workloads, plus config and an Ingress
  overlays/dev/         1 replica each, in-cluster Redis
  overlays/prod/        3 web replicas, Azure Cache for Redis, no in-cluster Redis
  sync-dashboard.sh     keeps the Grafana dashboard copy honest
```

The local-only emulators — Cosmos DB and Snowflake — are deliberately absent.
They exist to avoid touching cloud services during development; deploying them
into a cluster would be deploying a fake of the thing you are standing next to.

## Deploying

```bash
# 1. Build and push images, then point the overlay at them.
#    Edit `images:` in overlays/<env>/kustomization.yaml -- OWNER is a placeholder.
docker build -t ghcr.io/OWNER/b2c-web:dev -f nestjs-b2c-app/infra/Dockerfile nestjs-b2c-app
docker build -t ghcr.io/OWNER/b2c-api:dev -f nestjs-b2c-api/infra/Dockerfile nestjs-b2c-api
docker push ghcr.io/OWNER/b2c-web:dev && docker push ghcr.io/OWNER/b2c-api:dev

# 2. Secrets, out of band -- never committed.
kubectl create namespace b2c
kubectl -n b2c create secret generic b2c-secrets \
  --from-literal=B2C_CLIENT_SECRET='...' \
  --from-literal=SESSION_SECRET="$(openssl rand -base64 32)" \
  --from-literal=REDIS_URL=''            # prod: the Azure Cache connection string

# 3. Apply.
kubectl apply -k k8s/overlays/dev

# 4. Watch it come up.
kubectl -n b2c get pods -w
```

Preview exactly what will be applied, without a cluster:

```bash
kubectl kustomize k8s/overlays/prod
```

## What differs per environment

| | dev | prod |
| --- | --- | --- |
| web replicas | 1 | 3 |
| api replicas | 1 | 2 |
| Redis | in-cluster Deployment | Azure Cache, via `REDIS_URL` in the Secret |
| `APP_ENV` | `dev` | `prod` |

Production **removes** the in-cluster Redis rather than leaving it running and
unused: it is a single replica with no persistence, so a restart would sign
everyone out. That is fine for dev and not for production.

Multiple web replicas only work because sessions live in Redis. With the
in-process store, users would be signed out whenever the load balancer moved
them between pods — which is why the app refuses to start in a non-local
environment without `REDIS_URL`.

## Probes

The web app, Prometheus and Grafana have ordinary HTTP health endpoints.

The **API does not**, and its probe reflects that. Its only route requires a
bearer token and answers `401` without one, and an `httpGet` probe treats `401`
as a failure — so probing `/hello` would restart perfectly healthy pods forever.
Readiness therefore probes the unauthenticated metrics port, which returns `200`
and proves the process is serving; liveness uses a plain TCP connect, so it
still holds if `METRICS_ENABLED=false`.

## Secrets

`base/secret.example.yaml` is a template and is **not** applied — it is not in
`kustomization.yaml`. Create the Secret out of band, as above.

For Azure, prefer the **Key Vault CSI driver** or **External Secrets Operator**
so the cluster holds a reference rather than the value, and rotation does not
mean re-running `kubectl create secret`.

## Grafana is not exposed

The Ingress covers the web app only. Grafana runs with anonymous viewer access
exactly as it does locally, so putting it behind a public Ingress would publish
your metrics to anyone who finds the host. Reach it deliberately instead:

```bash
kubectl -n b2c port-forward svc/grafana 3002:3000
```

Put real authentication in front of it before exposing it.

The Ingress also ships without an `ingressClassName`, because the right value
differs between AGIC, ingress-nginx and Application Gateway for Containers, and
a wrong one produces an Ingress that silently routes nowhere. Set it, and the
host, in your overlay.

## The duplicated dashboard

Kustomize will not read files outside its own directory, and `kubectl -k`
provides no way to relax that, so the Grafana dashboard exists both under
`observability/` (for Compose) and under `k8s/base/dashboards/`. They are the
same file and must stay that way:

```bash
./k8s/sync-dashboard.sh          # copy observability/ -> k8s/base/
./k8s/sync-dashboard.sh --check  # fail if they differ; for CI
```
