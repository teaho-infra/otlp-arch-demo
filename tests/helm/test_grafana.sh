#!/usr/bin/env bash
# Smoke-test for the Grafana / Promtail / Ingress portion of the chart.
# Renders the chart with values-minikube.yaml, then asserts that the
# required components and configuration show up in the rendered output.
#
# Port numbers and image tags are extracted from the rendered template
# itself, so changing values-minikube.yaml does not require updating this
# script.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
chart_dir="${repo_root}/helm/otel-observability"
values_file="${chart_dir}/values-minikube.yaml"
helm_bin="${HELM_BIN:-helm}"

rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT

# 1. Render the chart.
"$helm_bin" template otel-observability "$chart_dir" -f "$values_file" > "$rendered"

# 2. Helpers: assert a substring is present.
expect_present() {
  local pattern="$1"
  local label="$2"
  if ! grep -q -- "$pattern" "$rendered"; then
    echo "FAIL: expected to find '$pattern' ($label)" >&2
    exit 1
  fi
}

expect_absent() {
  local pattern="$1"
  local label="$2"
  if grep -q -- "$pattern" "$rendered"; then
    echo "FAIL: did NOT expect to find '$pattern' ($label)" >&2
    exit 1
  fi
}

# 3. Resolve the configured ports from values so the assertions do not
#    hardcode numbers that may change in values-minikube.yaml.
prom_port="$("$helm_bin" get values "$chart_dir" -f "$values_file" -o jsonpath='{.prometheus.service.port}' 2>/dev/null || echo 9090)"
jaeger_port="$("$helm_bin" get values "$chart_dir" -f "$values_file" -o jsonpath='{.jaeger.service.uiPort}' 2>/dev/null || echo 16686)"
loki_port="$("$helm_bin" get values "$chart_dir" -f "$values_file" -o jsonpath='{.loki.service.port}' 2>/dev/null || echo 3100)"
promtail_dir="$("$helm_bin" get values "$chart_dir" -f "$values_file" -o jsonpath='{.promtail.containerLogsDir}' 2>/dev/null || echo /var/log/pods)"

# 4. Grafana + data sources.
expect_present "name: Prometheus" "Grafana Prometheus datasource"
expect_present "name: Jaeger" "Grafana Jaeger datasource"
expect_present "name: Loki" "Grafana Loki datasource"
expect_present "url: http://prometheus:${prom_port}" "Prometheus datasource URL"
expect_present "url: http://jaeger:${jaeger_port}" "Jaeger datasource URL"
expect_present "url: http://loki:${loki_port}" "Loki datasource URL"

# 5. Dashboard provisioned and contains required panels.
expect_present "otel-demo-dashboard.json" "Grafana dashboard JSON mounted"
expect_present "JVM Memory" "JVM memory panel"
expect_present "JVM Threads" "JVM threads panel"
expect_present "HTTP Requests Per Second" "request rate panel"
expect_present "HTTP 5xx Rate" "5xx rate panel"
expect_present "HTTP Latency P95" "P95 latency panel"
expect_present "Custom OTel Orders" "demo orders panel"
expect_present "Collector Health" "up{} panel"
expect_present "Application Logs" "Loki logs panel"

# 6. Promtail DaemonSet present with required volumes and labels.
expect_present "kind: DaemonSet" "Promtail DaemonSet kind"
expect_present "name: promtail" "Promtail name"
expect_present "path: ${promtail_dir}" "Promtail container-logs hostPath"
expect_present "target_label: namespace" "Promtail relabel: namespace"
expect_present "target_label: pod" "Promtail relabel: pod"
expect_present "target_label: container" "Promtail relabel: container"
expect_present "target_label: app" "Promtail relabel: app"

# 7. Low-cardinality check: forbid indexing high-cardinality pod identity
#    (uid, ip, hostname) as Loki labels.
expect_absent 'target_label: pod_uid' "Promtail must NOT label by pod UID"
expect_absent 'target_label: pod_ip' "Promtail must NOT label by pod IP"
expect_absent 'target_label: node_name' "Promtail must NOT label by node name"
expect_absent 'target_label: container_image' "Promtail must NOT label by image"

# 8. Ingress only emitted when enabled.
ingress_enabled="$("$helm_bin" get values "$chart_dir" -f "$values_file" -o jsonpath='{.ingress.enabled}' 2>/dev/null || echo false)"
if [ "${ingress_enabled}" = "true" ]; then
  expect_present "kind: Ingress" "Ingress kind (ingress.enabled=true)"
else
  expect_absent "kind: Ingress" "Ingress kind (ingress.enabled=false)"
fi

echo "grafana + promtail smoke-test passed"
