# Helm charts

Helm owns **releases**: what is deployed, at which version, and how to move
back. Terraform owns the infrastructure underneath (cluster, registry, cache,
Key Vault) and hands its outputs in as values.

```
helm/
  b2c-web/            the NestJS web app: Deployment, Service, ConfigMap, Secret
  b2c-api/            the NestJS API:     Deployment, Service, ConfigMap
  b2c-observability/  Prometheus and Grafana, dashboard provisioned
```

Redis still ships only as the Kustomize manifests under `k8s/`; a chart for it
can follow the same shape, or these three can become subcharts of an umbrella
`b2c` chart later.

## Installing on a local cluster

You need a cluster (kind, minikube, or Docker Desktop's Kubernetes), Helm 3, and
the app image built on this machine.

```bash
# 1. Build the image and put it where the cluster's runtime can see it.
docker build -t b2c-web:local -f nestjs-b2c-app/infra/Dockerfile nestjs-b2c-app
kind load docker-image b2c-web:local --name b2c     # kind
# minikube image load b2c-web:local                 # minikube
# Docker Desktop shares its daemon with the cluster, nothing to load

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

## Installing the API

Same shape, one release along side the other, and **the same tenant and user
flow**. The API validates the token the web app was issued, so a different
tenant means keys it does not trust.

```bash
docker build -t b2c-api:local -f nestjs-b2c-api/infra/Dockerfile nestjs-b2c-api
kind load docker-image b2c-api:local --name b2c

helm install b2c-api ./helm/b2c-api -n b2c \
  --set b2c.tenantName=your-tenant \
  --set b2c.policyName=<the exact user-flow name>

# Point the web app's demo links at this release.
helm upgrade b2c-web ./helm/b2c-web -n b2c --set demoApiUrl=http://b2c-api:3001/hello
```

**Check**: a 401 is the success case, because the endpoint requires a bearer
token and `curl` sent none:

```bash
kubectl -n b2c port-forward svc/b2c-api 3001:3001 9464:9464
curl -i http://localhost:3001/hello                       # 401 Unauthorized
curl -s http://localhost:9464/metrics | grep api_requests_total | head -3
```

The API holds no credentials, since it validates tokens with the tenant's
public signing keys, so this chart creates **no Secret at all**. It also has no
session state, so `replicaCount` is free to be whatever you want.

| value | default | what it does |
| --- | --- | --- |
| `b2c.tenantName` / `b2c.policyName` | placeholders | must match the web app's; the pod crash-loops until they resolve |
| `b2c.discoveryUrl` | `""` | full URL, for the cases the derived one cannot express |
| `b2c.audience` | `""` | **unset means any token this tenant signed is accepted**, see below |
| `b2c.requiredScope` | `""` | also require this scope in the token's `scp` claim |
| `corsOrigin` | `http://localhost:3000` | browser origin allowed to call the API directly |
| `metrics.enabled` | `true` | opens the metrics port, and decides the readiness probe |

`b2c.audience` empty is what lets the web app's existing bearer token work with
no second app registration, and it is a real weakening: any unexpired token the
tenant signed is accepted, including tokens issued to other applications. Set it
to this API's own client ID before deploying anywhere real. The pod says so in
its own start-up logs, loudly.

**Probes.** The API's only route answers 401 without a token, and an `httpGet`
probe reads 401 as a failure, so probing `/hello` would restart healthy pods
forever. Readiness probes the unauthenticated metrics port instead; with
`metrics.enabled=false` there is no unauthenticated route left, so it falls back
to a TCP connect. Liveness is always a TCP connect.

**If you scrape with the Prometheus from `k8s/`**, note that it targets
`api:9464` by name while this chart names the Service after the release. Either
install as `helm install api ./helm/b2c-api`, or point the scrape config at
`b2c-api:9464`.

## What the defaults give you

A web app that needs nothing else running: `appEnv: local`, so sessions live in
the pod and the session cookie's `Secure` flag stays off, because a Secure cookie over
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

## Installing observability

Prometheus and Grafana are one release, not two. Grafana's only datasource is
this Prometheus, so the datasource URL is derived from the release rather than
configured, and there is no way to end up pointing at a Prometheus nobody
deployed.

```bash
helm install b2c-observability ./helm/b2c-observability -n b2c

kubectl -n b2c port-forward svc/b2c-observability-grafana 3300:3000
```

Open <http://localhost:3300/dashboards> and pick **B2C / API calls**. Port 3300
only to leave 3000 free for the web app.

**What it scrapes** is the one value you are likely to change. `scrapeTargets`
defaults to `b2c-api:9464`, which is the Service the API chart creates when its
release is named `b2c-api`. Named it something else, and the target sits `down`
until you say so:

```bash
kubectl -n b2c get svc                    # what is the API's Service actually called?
helm upgrade b2c-observability ./helm/b2c-observability -n b2c \
  --set scrapeTargets[0].address=api:9464
```

Verify before blaming an empty panel, because a `down` target and a quiet API
look identical on a dashboard:

```bash
kubectl -n b2c port-forward svc/b2c-observability-prometheus 9090:9090
curl -s 'http://localhost:9090/api/v1/targets?state=active' | grep -o '"health":"[a-z]*"'
```

| value | default | what it does |
| --- | --- | --- |
| `scrapeTargets` | `b2c-api:9464` | list of `{name, address, labels}`; address is a Service name in this namespace |
| `prometheus.retention` | `7d` | storage is an `emptyDir`, so a restart drops history regardless |
| `prometheus.scrapeInterval` | `10s` | also becomes Grafana's `timeInterval` |
| `grafana.anonymous.enabled` | `true` | no login, and no protection either; see below |
| `prometheus.enabled` / `grafana.enabled` | `true` | install one without the other |

**Adding a dashboard** is dropping a JSON file into `b2c-observability/dashboards/`.
Every file matching `dashboards/*.json` is provisioned, and Grafana's pod rolls
when any of them change, so no template needs editing. `b2c-api-calls.json` is a
copy of `observability/grafana/dashboards/b2c-api-calls.json`, because neither
Helm nor kustomize reads files outside its own directory. `./k8s/sync-dashboard.sh`
refreshes both copies and `--check` fails when either has drifted.

**Grafana has no authentication.** Anonymous Viewer access is on, matching the
Compose stack, so anyone who can reach the Service can read your metrics. That
is fine behind `kubectl port-forward` and not fine behind an Ingress. Set
`grafana.anonymous.enabled=false`, or put real auth in front of it, before
exposing it.

## Secrets

By default the chart creates a Secret holding `SESSION_SECRET` and
`B2C_CLIENT_SECRET`. The session secret is generated once and read back from the
cluster on every upgrade, since regenerating it would sign every user out on a change
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
then its outputs become values here: `image.repository` from the registry login
server, `redis.url` from the cache, `appBaseUrl` from the ingress host. Helm
never provisions infrastructure, and Terraform never deploys the app: keeping a
per-commit rollout out of a state file means a `terraform destroy` typo cannot
take the cluster with it.
