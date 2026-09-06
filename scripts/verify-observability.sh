#!/usr/bin/env bash
# End-to-end verification for the otel-observability deployment on Minikube.
#
# Waits for all Pods to be Ready, calls the demo app's HTTP endpoints,
# queries Prometheus / Jaeger / Loki via minikube service URLs (NOT in-cluster
# DNS), and asserts that Grafana data sources are provisioned. Exits
# non-zero on any failure.
#
# Usage: scripts/verify-observability.sh [--help]
set -euo pipefail

usage() {
  cat <<EOF
Usage: scripts/verify-observability.sh [--help]

End-to-end verification of the otel-observability stack on Minikube.
Exits non-zero if any readiness, HTTP, metrics, trace, log, or Grafana
datasource check fails.

Environment overrides:
  VERIFY_TIMEOUT=<seconds>   Override the per-check wait timeout (default 180).
  VERIFY_NAMESPACE=<ns>       Override the namespace (default observability).
EOF
}
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then usage; exit 0; fi
if [[ $# -ne 0 ]]; then echo "error: unknown argument: $1" >&2; usage >&2; exit 2; fi

timeout="${VERIFY_TIMEOUT:-180s}"
namespace="${VERIFY_NAMESPACE:-observability}"

for cmd in minikube kubectl curl; do
  command -v "$cmd" >/dev/null || { echo "error: $cmd is required" >&2; exit 1; }
done

fail() { echo "FAIL: $1" >&2; exit 1; }
ok()   { echo "ok:   $1"; }

# 1. Wait for every Pod in the namespace to be Ready.
echo "waiting for Pods in namespace $namespace (timeout=$timeout)..."
kubectl wait --for=condition=Ready pod \
  -l app.kubernetes.io/instance=otel-observability \
  -n "$namespace" --timeout="$timeout" \
  || fail "pods not Ready in $timeout"
ok "all pods Ready"

# 2. Resolve service URLs from Minikube (host-side, not in-cluster DNS).
app_url="$(minikube service demo -n "$namespace" --url 2>/dev/null | head -n 1 || true)"
grafana_url="$(minikube service grafana -n "$namespace" --url 2>/dev/null | head -n 1 || true)"
prom_url="$(minikube service prometheus -n "$namespace" --url 2>/dev/null | head -n 1 || true)"
jaeger_url="$(minikube service jaeger -n "$namespace" --url 2>/dev/null | head -n 1 || true)"
loki_url="$(minikube service loki -n "$namespace" --url 2>/dev/null | head -n 1 || true)"
[[ -n "$app_url" ]]    || fail "could not resolve demo service URL"
[[ -n "$grafana_url" ]] || fail "could not resolve grafana service URL"
[[ -n "$prom_url" ]]   || fail "could not resolve prometheus service URL"
[[ -n "$jaeger_url" ]] || fail "could not resolve jaeger service URL"
[[ -n "$loki_url" ]]   || fail "could not resolve loki service URL"
ok "resolved 5 service URLs"

# 3. Demo app HTTP endpoints.
curl --fail --silent "${app_url}/api/hello" | grep -q 'Hello' || fail "/api/hello did not return expected body"
ok "/api/hello"

curl --fail --silent "${app_url}/api/orders/1001" | grep -q '1001' || fail "/api/orders/1001 did not return expected id"
ok "/api/orders/1001"

curl --fail --silent "${app_url}/api/load?count=50" | grep -q '50' || fail "/api/load?count=50 did not return expected count"
ok "/api/load?count=50"

code="$(curl --silent --output /dev/null --write-out '%{http_code}' "${app_url}/api/error")"
[[ "$code" == "500" ]] || fail "/api/error expected HTTP 500, got $code"
ok "/api/error returned 500"

# 4. Prometheus queries.
for metric in up demo_orders_total demo_errors_total http_server_requests_seconds_count; do
  resp="$(curl --fail --silent --get "${prom_url}/api/v1/query" --data-urlencode "query=$metric")" \
    || fail "prometheus query $metric failed"
  echo "$resp" | grep -q '"status":"success"' || fail "prometheus query $metric did not return success"
  ok "prometheus $metric"
done

# 5. Jaeger services endpoint must list the demo service.
jaeger_resp="$(curl --fail --silent "${jaeger_url}/api/services")" || fail "jaeger /api/services failed"
echo "$jaeger_resp" | grep -q 'otel-springboot-demo' || fail "jaeger does not list otel-springboot-demo service"
ok "jaeger lists otel-springboot-demo"

# 6. Loki log query.
loki_resp="$(curl --fail --silent -G "${loki_url}/loki/api/v1/query_range" \
  --data-urlencode 'query={namespace="observability",app="otel-springboot-demo"}' \
  --data-urlencode 'limit=10')" || fail "loki query_range failed"
echo "$loki_resp" | grep -q '"status":"success"' || fail "loki query did not return success"
ok "loki query_range for demo logs"

# 7. Grafana data sources.
for ds in Prometheus Jaeger Loki; do
  resp="$(curl --fail --silent "${grafana_url}/api/datasources/name/${ds}")" || fail "grafana datasource ${ds} not found"
  ok "grafana datasource ${ds}"
done

echo
echo "observability verification passed"
