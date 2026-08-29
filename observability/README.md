# API call metrics — Prometheus + Grafana

A dashboard over the NestJS API's call volume, outcome and latency.

```bash
docker compose -f observability/docker-compose.yml up -d
```

| | |
| --- | --- |
| Grafana | http://localhost:3002 — dashboard **B2C / B2C API — calls** |
| Prometheus | http://localhost:9090 |

The API must be running with its metrics port reachable (9464 by default). Both
Grafana and Prometheus are provisioned from files in this directory, so the
dashboard is present on first start with no clicking.

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

## Notes

* Grafana runs with anonymous viewer access and no login, which is local
  convenience only. Remove `GF_AUTH_ANONYMOUS_*` before exposing it anywhere.
* Dashboards are provisioned with `allowUiUpdates: false`, so the file stays the
  source of truth. To keep a change made in the UI, export the JSON back over
  `grafana/dashboards/b2c-api-calls.json`.
* Ports publish to `127.0.0.1` only, as with the other stacks here.
