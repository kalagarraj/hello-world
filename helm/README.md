# Helm charts

Helm owns **releases**: what is deployed, at which version, and how to move
back. Terraform owns the infrastructure underneath — cluster, registry, cache,
Key Vault — and hands its outputs in as values.

```
helm/
  b2c-web/     the NestJS web app: Deployment, Service, ConfigMap, Secret
```

Only the web app so far. The API, Redis and the observability stack still ship
as the Kustomize manifests under `k8s/`; charts for those can follow the same
shape, or become subcharts of an umbrella `b2c` chart later.

## Installing on a local cluster

You need a cluster (kind, minikube, or Docker Desktop's Kubernetes), Helm 3, and
the app image built on this machine.

```bash
# 1. Build the image and put it where the cluster's runtime can see it.
docker build -t b2c-web:local -f nestjs-b2c-app/infra/Dockerfile nestjs-b2c-app
kind load docker-image b2c-web:local --name b2c     # kind
# minikube image load b2c-web:local                 # minikube
# Docker Desktop shares its daemon with the cluster — nothing to load

# 2. Install, with your own tenant and client ID.
helm install b2c-web ./helm/b2c-web \
  --namespace b2c --create-namespace \
  --set b2c.tenantName=your-tenant \
  --set b2c.clientId=00000000-0000-0000-0000-000000000000

# 3. Reach it.
kubectl -n b2c rollout status deploy/b2c-web
kubectl -n b2c port-forward svc/b2c-web 3000:3000
```

Open <http://localhost:3000>. Port 3000 is not arbitrary: `appBaseUrl` makes the
redirect URI `http://localhost:3000/auth/callback`, which has to match one
registered on the app registration.

Prefer a values file over a wall of `--set` once you have more than a couple:

```bash
helm install b2c-web ./helm/b2c-web -n b2c --create-namespace -f my-values.yaml
```

## What the defaults give you

A web app that needs nothing else running: `appEnv: local`, so sessions live in
the pod and the session cookie's `Secure` flag stays off — a Secure cookie over
plain `http://localhost` is dropped by the browser, and the login would appear
to succeed and land back on the home page.

The consequence is one replica. Sessions in a pod are not shared, so a second
replica would sign people out whenever the Service moved them; the chart fails
the install rather than let that reach a cluster:

```
Error: execution error at (b2c-web/templates/deployment.yaml:7:4):
replicaCount > 1 needs redis.url: without a shared session store each replica has its own sessions
```

Point it at a Redis and both restrictions lift:

```bash
helm upgrade b2c-web ./helm/b2c-web -n b2c \
  --set appEnv=dev --set redis.url=redis://redis:6379 --set replicaCount=2
```

## Values worth knowing

| value | default | what it does |
| --- | --- | --- |
| `image.repository` / `image.tag` | `b2c-web` / `local` | `pullPolicy: IfNotPresent`, because the image was built here, not pulled |
| `appEnv` | `local` | anything else expects a shared session store |
| `appBaseUrl` | `http://localhost:3000` | drives the redirect URI sent to B2C |
| `b2c.tenantName` / `b2c.clientId` | placeholders | until they are yours the pod crash-loops on start-up |
| `b2c.clientSecret` | `""` | empty means a public client: PKCE only, no secret at the token endpoint |
| `sessionSecret` | `""` | generated on first install, reused on upgrade |
| `existingSecret` | `""` | use a Secret you created yourself; the chart then creates none |
| `redis.url` | `""` | shared sessions, and the gate on more than one replica |
| `demoApiUrl` | `""` | the API the demo links call, e.g. `http://api:3001/hello` |

## Secrets

By default the chart creates a Secret holding `SESSION_SECRET` and
`B2C_CLIENT_SECRET`. The session secret is generated once and read back from the
cluster on every upgrade — regenerating it would sign every user out on a change
that had nothing to do with sessions.

For anything beyond a laptop, don't put the real secret in values at all. Create
it out of band, or project it from Key Vault with the CSI driver or External
Secrets Operator, and point the chart at it:

```bash
helm upgrade b2c-web ./helm/b2c-web -n b2c --set existingSecret=b2c-secrets
```

The chart then creates no Secret of its own and never overwrites yours. Values
files with real secrets in them get committed by accident; Secrets projected
from a vault do not.

## Releases

This is what Helm buys over `kubectl apply`:

```bash
helm history b2c-web -n b2c        # every revision, with what happened
helm rollback b2c-web 1 -n b2c     # back to revision 1, config and all
helm uninstall b2c-web -n b2c      # everything the release created, gone
helm diff upgrade ...              # with the helm-diff plugin, before you apply
```

A ConfigMap or Secret change rolls the pods on its own: the pod template carries
`checksum/config` and `checksum/secret` annotations, without which an upgrade
that edits only configuration leaves the old values running in a pod nobody
restarted.

Render without touching a cluster, to see exactly what an install would send:

```bash
helm template b2c-web ./helm/b2c-web --set b2c.tenantName=your-tenant
helm lint ./helm/b2c-web
```

Note that `helm template` cannot read the cluster, so it shows a freshly
generated `SESSION_SECRET` every time. An actual upgrade keeps the installed one.

## Where Terraform stops and Helm starts

Terraform creates the cluster, the registry, the Azure Cache and the Key Vault,
then its outputs become values here — `image.repository` from the registry login
server, `redis.url` from the cache, `appBaseUrl` from the ingress host. Helm
never provisions infrastructure, and Terraform never deploys the app: keeping a
per-commit rollout out of a state file means a `terraform destroy` typo cannot
take the cluster with it.
