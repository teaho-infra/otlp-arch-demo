#!/usr/bin/env bash
# End-to-end verification for the otel-observability deployment.
#
# Waits for all Pods to be Ready, calls the demo app's HTTP endpoints,
# queries Prometheus / Jaeger / Loki, and asserts that Grafana data sources
# are provisioned. Explicit service URL overrides support Kind port-forwards;
# without overrides, URLs are resolved through Minikube.
#
# Usage: scripts/verify-observability.sh [--help]
set -euo pipefail

usage() {
  cat <<EOF
Usage: scripts/verify-observability.sh [--help]

End-to-end verification of the otel-observability stack on Kubernetes.
Exits non-zero if any readiness, HTTP, metrics, trace, log, or Grafana
datasource check fails.

Environment overrides:
  VERIFY_TIMEOUT=<seconds>   Per-check wait timeout (default 180s).
  VERIFY_NAMESPACE=<ns>     Namespace (default observability).
  VERIFY_APP_URL=<url>      Demo URL (for example http://127.0.0.1:18080).
  VERIFY_GRAFANA_URL=<url>  Grafana URL (for example http://127.0.0.1:13000).
  VERIFY_PROM_URL=<url>     Prometheus URL (for example http://127.0.0.1:19090).
  VERIFY_JAEGER_URL=<url>   Jaeger URL (for example http://127.0.0.1:16686).
  VERIFY_LOKI_URL=<url>     Loki URL (for example http://127.0.0.1:13100).
  VERIFY_GRAFANA_USER=<user>      Grafana API user (default admin).
  VERIFY_GRAFANA_PASSWORD=<pass>  Grafana API password (default admin).

Provide all five URL variables for Kind port-forwards. If none are provided,
the script resolves service URLs with Minikube.
EOF
}
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then usage; exit 0; fi
if [[ $# -ne 0 ]]; then echo "error: unknown argument: $1" >&2; usage >&2; exit 2; fi

timeout="${VERIFY_TIMEOUT:-180s}"
namespace="${VERIFY_NAMESPACE:-observability}"
grafana_user="${VERIFY_GRAFANA_USER:-admin}"
grafana_password="${VERIFY_GRAFANA_PASSWORD:-admin}"

for cmd in kubectl curl; do
  command -v "$cmd" >/dev/null || { echo "error: $cmd is required" >&2; exit 1; }
done

fail() { echo "FAIL: $1" >&2; exit 1; }
ok()   { echo "ok:   $1"; }

# 1. Wait for every Pod in the namespace to be Ready.
echo "waiting for Pods in namespace $namespace (timeout=$timeout)..."
kubectl wait --for=condition=Ready pod --all \
  -n "$namespace" --timeout="$timeout" \
  || fail "pods not Ready in $timeout"
ok "all pods Ready"

# 2. Use explicit URLs (Kind port-forwards) or resolve all URLs via Minikube.
app_url="${VERIFY_APP_URL:-}"
grafana_url="${VERIFY_GRAFANA_URL:-}"
prom_url="${VERIFY_PROM_URL:-}"
jaeger_url="${VERIFY_JAEGER_URL:-}"
loki_url="${VERIFY_LOKI_URL:-}"

if [[ -z "$app_url$grafana_url$prom_url$jaeger_url$loki_url" ]]; then
  command -v minikube >/dev/null || { echo "error: provide all VERIFY_*_URL variables or install minikube" >&2; exit 1; }
  app_url="$(minikube service demo -n "$namespace" --url 2>/dev/null | head -n 1 || true)"
  grafana_url="$(minikube service grafana -n "$namespace" --url 2>/dev/null | head -n 1 || true)"
  prom_url="$(minikube service prometheus -n "$namespace" --url 2>/dev/null | head -n 1 || true)"
  jaeger_url="$(minikube service jaeger -n "$namespace" --url 2>/dev/null | head -n 1 || true)"
  loki_url="$(minikube service loki -n "$namespace" --url 2>/dev/null | head -n 1 || true)"
elif [[ -z "$app_url" || -z "$grafana_url" || -z "$prom_url" || -z "$jaeger_url" || -z "$loki_url" ]]; then
  echo "error: provide all five VERIFY_*_URL variables, or none for Minikube" >&2
  exit 1
fi
[[ -n "$app_url" ]]    || fail "could not resolve demo service URL"
[[ -n "$grafana_url" ]] || fail "could not resolve grafana service URL"
[[ -n "$prom_url" ]]   || fail "could not resolve prometheus service URL"
[[ -n "$jaeger_url" ]] || fail "could not resolve jaeger service URL"
[[ -n "$loki_url" ]]   || fail "could not resolve loki service URL"
ok "resolved 5 service URLs"

# 3. Demo app HTTP endpoints.
curl --fail --silent "${app_url}/api/hello" | grep -qi 'hello opentelemetry' || fail "/api/hello did not return expected body"
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
if echo "$loki_resp" | grep -Eq '"result"[[:space:]]*:[[:space:]]*\[[[:space:]]*\]'; then
  fail "loki query returned no demo logs"
fi
ok "loki query_range for demo logs"

# 7. Grafana data sources.
for ds in Prometheus Jaeger Loki; do
  resp="$(curl --fail --silent -u "${grafana_user}:${grafana_password}" "${grafana_url}/api/datasources/name/${ds}")" || fail "grafana datasource ${ds} not found"
  ok "grafana datasource ${ds}"
done

echo
echo "observability verification passed"
