#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../helm/otel-observability" && pwd)"
helm_bin="${HELM_BIN:-helm}"
rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT

"$helm_bin" template otel-observability "$chart_dir" \
  -f "$chart_dir/values-minikube.yaml" > "$rendered"

grep -q 'endpoint: 0.0.0.0:4317' "$rendered"
grep -q 'endpoint: 0.0.0.0:4318' "$rendered"
grep -q 'memory_limiter:' "$rendered"
grep -q 'resource:' "$rendered"
grep -q 'batch:' "$rendered"
grep -q 'traces:' "$rendered"
grep -q 'metrics:' "$rendered"
grep -q 'logs:' "$rendered"
grep -q 'endpoint: jaeger:4317' "$rendered"
grep -q 'endpoint: http://loki:3100/loki/api/v1/push' "$rendered"
! grep -Eq 'order[_-]?id|request[_-]?id' "$rendered"
