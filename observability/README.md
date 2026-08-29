# API call metrics — Prometheus + Grafana

A dashboard over the NestJS API's call volume, outcome and latency.

## Steps

From the repository root, in order:

```bash
# 1. The shared network. Skip if you have already started an app stack --
#    their npm scripts create it. Safe to run twice.
docker network create b2c-shared 2>/dev/null || true

# 2. The API, which is what gets measured.
cd nestjs-b2c-api && npm run docker:up && cd ..

# 3. Prometheus and Grafana.
docker compose -f observability/docker-compose.yml up -d
```

| | |
| --- | --- |
| Grafana | http://localhost:3002 — dashboard **B2C / B2C API — calls** |
| Prometheus | http://localhost:9090 |

Both are provisioned from files in this directory, so the dashboard is there on
first start with no clicking.

### The "Sign in" button is normal

With anonymous access on, Grafana still shows a **Sign in** button — you are
already browsing as an anonymous viewer and do not need it. Use it only to edit
something; the account is `admin` / `admin`.

If instead you are *forced* to a login page, anonymous access did not take
effect. Check the container picked up the settings:

```bash
docker compose -f observability/docker-compose.yml exec grafana env | grep GF_AUTH
```

### If the dashboard is missing or every panel says "No data"

Work through it in this order — each command answers one question.

```bash
# 1. Did provisioning succeed? Datasource and dashboard errors both show here.
docker compose -f observability/docker-compose.yml logs grafana | grep -iE "provisioning|error"

# 2. Does Grafana have the Prometheus datasource?
curl -s http://localhost:3002/api/datasources | python3 -m json.tool

# 3. Did the dashboard load?
curl -s http://localhost:3002/api/search?query=B2C | python3 -m json.tool

# 4. Is Prometheus scraping the API?
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -E '"health"|"scrapeUrl"|lastError'

# 5. Does Prometheus actually hold the metric?
curl -s 'http://localhost:9090/api/v1/query?query=api_requests_total' | python3 -m json.tool
```

Step 4 `"health": "down"` means Prometheus cannot reach the API — see the
network check below. Step 5 returning an empty result with a healthy target
means the API has simply not served any requests yet: generate traffic.

### Check it is scraping

```bash
open http://localhost:9090/targets      # b2c-api should read UP
```

`DOWN` means Prometheus cannot reach the API. Prometheus scrapes it as
`api:9464` over the `b2c-shared` network, so the usual causes are the API stack
not running, or it not being attached to that network:

```bash
docker network inspect b2c-shared --format '{{range .Containers}}{{.Name}} {{end}}'
```

Both the API container and `prometheus` should appear. If you run the API on
your machine rather than in Docker, change the target in
`prometheus/prometheus.yml` to `host.docker.internal:9464` and restart
Prometheus.

### Make the panels show something

An idle API produces flat zeroes. Generate some traffic — the demo links in the
web app do this, or:

```bash
curl -s -o /dev/null http://localhost:3001/hello          # a 401
curl -s -o /dev/null -H "Authorization: Bearer $TOKEN" http://localhost:3001/hello
```

Panels fill within a scrape interval or two (10s).

## What the API exposes

Metrics are served on a **separate port** from the API itself. The API keeps
exactly one route, and scrape traffic never touches the authenticated surface —
publish 9464 to Prometheus, never to the internet.

| Metric | Type | Labels |
| --- | --- | --- |
| `api_requests_total` | counter | `method`, `route`, `status`, `status_class` |
| `api_request_duration_seconds` | histogram | `method`, `route`, `status_class` |
| `api_auth_results_total` | counter | `result` (`accepted` / `rejected`) |

Plus the default Node process and runtime metrics.

`route` is the matched Express *pattern*, and anything unmatched is labelled
`unmatched` rather than by its raw URL — otherwise a path scanner would mint a
new time series per probe and bloat the database.

## The panels

Headline numbers are stat tiles rather than charts, because a single current
value has no shape to plot: **call rate**, **error rate**, **p95 latency** and
**token rejection rate**. Below them, change over time: **call rate by status
class** and **latency percentiles**. Then identity: **call rate by route**, and
a **table** of calls by route and status for exact figures.

Two deliberate choices:

* **Error rate counts only 5xx.** A 401 is the API working — refusing a bad
  token — not failing, so folding rejections into an error rate would make a
  healthy API look broken during a token misconfiguration. Rejections get their
  own tile, where a jump against flat traffic is the readable signal.
* **Latency percentiles share one panel and one axis.** They are the same
  measure in the same unit. A second measure would get its own panel rather than
  a second y-axis.

Status classes use the reserved status colours — green 2xx, orange 4xx, red 5xx
— which are never reused as an ordinary series colour elsewhere on the board.

## Azure Monitor

The same Grafana provisions an **Azure Monitor** datasource for the deployed
API, so App Insights request metrics sit beside the local Prometheus ones. It
stays inert until you supply a service principal:

```bash
export AZURE_TENANT_ID=... AZURE_CLIENT_ID=... AZURE_CLIENT_SECRET=... AZURE_SUBSCRIPTION_ID=...
docker compose -f observability/docker-compose.yml up -d
```

Unset, the datasource is provisioned but fails to authenticate — which is the
honest state, rather than pretending to be configured.

The bundled dashboard queries **Prometheus only**; it has not been built against
Azure Monitor's own metric names (`requests/count`, `requests/duration`), which
differ from the ones here.

## This stack is optional

Nothing in the request path of either app talks to Prometheus or Grafana, so
neither app cares whether this stack is running — the API exposes metrics and is
indifferent to whether anyone scrapes them. Conversely, if the API's metrics port
cannot bind, the API logs it and keeps serving; Prometheus shows the target as
down and the panels go empty, which is the correct signal rather than an outage.

## Notes

* Grafana runs with anonymous viewer access and no login, which is local
  convenience only. Remove `GF_AUTH_ANONYMOUS_*` before exposing it anywhere.
* Dashboards are provisioned with `allowUiUpdates: false`, so the file stays the
  source of truth. To keep a change made in the UI, export the JSON back over
  `grafana/dashboards/b2c-api-calls.json`.
* Ports publish to `127.0.0.1` only, as with the other stacks here.
