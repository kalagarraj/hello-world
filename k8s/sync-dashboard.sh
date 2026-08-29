#!/bin/sh
# Kustomize refuses to read files outside its own directory, and `kubectl -k`
# offers no way to relax that, so the dashboard has to exist under k8s/base as
# well as under observability/. This keeps the copy honest.
#
#   ./k8s/sync-dashboard.sh          copy observability/ -> k8s/base/
#   ./k8s/sync-dashboard.sh --check  fail if they differ (for CI)
set -e

SRC="observability/grafana/dashboards/b2c-api-calls.json"
DST="k8s/base/dashboards/b2c-api-calls.json"

if [ "$1" = "--check" ]; then
  if diff -q "$SRC" "$DST" >/dev/null 2>&1; then
    echo "in sync: $DST"
  else
    echo "OUT OF SYNC: $DST differs from $SRC" >&2
    echo "run ./k8s/sync-dashboard.sh" >&2
    exit 1
  fi
else
  cp "$SRC" "$DST"
  echo "copied $SRC -> $DST"
fi
