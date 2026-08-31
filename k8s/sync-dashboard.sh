#!/bin/sh
# Neither kustomize nor Helm will read files outside its own directory, so the
# dashboard has to exist under k8s/base and under helm/b2c-observability as well
# as under observability/. This keeps those copies honest.
#
#   ./k8s/sync-dashboard.sh          copy observability/ -> the others
#   ./k8s/sync-dashboard.sh --check  fail if any differ (for CI)
set -e

SRC="observability/grafana/dashboards/b2c-api-calls.json"
DESTS="k8s/base/dashboards/b2c-api-calls.json helm/b2c-observability/dashboards/b2c-api-calls.json"

status=0
for dst in $DESTS; do
  if [ "$1" = "--check" ]; then
    if diff -q "$SRC" "$dst" >/dev/null 2>&1; then
      echo "in sync: $dst"
    else
      echo "OUT OF SYNC: $dst differs from $SRC" >&2
      status=1
    fi
  else
    cp "$SRC" "$dst"
    echo "copied $SRC -> $dst"
  fi
done

if [ "$status" -ne 0 ]; then
  echo "run ./k8s/sync-dashboard.sh" >&2
fi
exit "$status"
