#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../helm/otel-observability" && pwd)"
helm_bin="${HELM_BIN:-helm}"
rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT

"$helm_bin" template otel-observability "$chart_dir" -f "$chart_dir/values-minikube.yaml" > "$rendered"
grep -q 'name: prometheus-data' "$rendered"
grep -q 'name: jaeger-data' "$rendered"
grep -q 'name: loki-data' "$rendered"
grep -q 'kind: StatefulSet' "$rendered"
grep -q 'storage.tsdb.retention.time=7d' "$rendered"
grep -q 'SPAN_STORAGE_TYPE' "$rendered"
grep -q 'retention_period: 7d' "$rendered"
grep -q 'demo:http_requests_per_second' "$rendered"
grep -q 'DemoServiceDown' "$rendered"
