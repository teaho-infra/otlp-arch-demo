#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for script in minikube-up.sh minikube-down.sh verify-observability.sh; do "$repo_root/scripts/$script" --help >/dev/null; done
if "$repo_root/scripts/minikube-down.sh" --unexpected >/dev/null 2>&1; then exit 1; fi
if "$repo_root/scripts/minikube-up.sh" --unexpected >/dev/null 2>&1; then exit 1; fi

help_output="$($repo_root/scripts/verify-observability.sh --help)"
for variable in VERIFY_APP_URL VERIFY_GRAFANA_URL VERIFY_PROM_URL VERIFY_JAEGER_URL VERIFY_LOKI_URL VERIFY_GRAFANA_USER VERIFY_GRAFANA_PASSWORD; do
  grep -q "$variable" <<<"$help_output"
done

fake_bin="$(mktemp -d)"
trap 'rm -rf "$fake_bin"' EXIT

cat >"$fake_bin/kubectl" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"app.kubernetes.io/instance"* ]]; then exit 1; fi
if [[ "$1" == "wait" && "$*" != *"--all"* ]]; then exit 1; fi
exit 0
EOF

cat >"$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
args="$*"
if [[ "$args" == *"api/datasources/name"* && "$args" != *"-u admin:admin"* ]]; then exit 1; fi
case "$args" in
  *api/hello*) echo 'hello opentelemetry' ;;
  *api/orders/1001*) echo '1001' ;;
  *api/load*) echo '50' ;;
  *api/error*) echo '500' ;;
  *api/services*) echo '{"data":["otel-springboot-demo"]}' ;;
  *query_range*)
    if [[ "${FAKE_EMPTY_LOKI:-0}" == "1" ]]; then
      echo '{"status":"success","data":{"result":[]}}'
    else
      echo '{"status":"success","data":{"result":[{}]}}'
    fi
    ;;
  *api/v1/query*) echo '{"status":"success"}' ;;
  *api/datasources/name/*) echo '{}' ;;
  *) exit 1 ;;
esac
EOF

chmod +x "$fake_bin/kubectl" "$fake_bin/curl"

PATH="$fake_bin:/usr/bin:/bin" \
VERIFY_APP_URL=http://demo.test \
VERIFY_GRAFANA_URL=http://grafana.test \
VERIFY_PROM_URL=http://prometheus.test \
VERIFY_JAEGER_URL=http://jaeger.test \
VERIFY_LOKI_URL=http://loki.test \
  "$repo_root/scripts/verify-observability.sh" >/dev/null

if PATH="$fake_bin:/usr/bin:/bin" \
FAKE_EMPTY_LOKI=1 \
VERIFY_APP_URL=http://demo.test \
VERIFY_GRAFANA_URL=http://grafana.test \
VERIFY_PROM_URL=http://prometheus.test \
VERIFY_JAEGER_URL=http://jaeger.test \
VERIFY_LOKI_URL=http://loki.test \
  "$repo_root/scripts/verify-observability.sh" >/dev/null 2>&1; then
  echo "FAIL: verification must reject an empty Loki result" >&2
  exit 1
fi
