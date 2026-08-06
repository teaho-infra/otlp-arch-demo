#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../helm/otel-observability" && pwd)"
rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT

helm lint "$chart_dir"
helm template otel-observability "$chart_dir" \
  -f "$chart_dir/values-minikube.yaml" > "$rendered"

grep -q 'name: observability' "$rendered"
grep -q 'name: otel-collector' "$rendered"
grep -q 'name: prometheus' "$rendered"
grep -q 'name: grafana' "$rendered"
grep -q 'name: jaeger' "$rendered"
grep -q 'name: loki' "$rendered"
grep -q 'name: promtail' "$rendered"
grep -q 'containerPort: 4317' "$rendered"
grep -q 'containerPort: 4318' "$rendered"
grep -q 'kind: PersistentVolumeClaim' "$rendered"
