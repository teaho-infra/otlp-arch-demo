# otel-observability Helm chart

Umbrella chart for running the Java 8 / Spring Boot 2.7 OpenTelemetry demo
plus a full local observability stack on Minikube.

## What's in the chart

| Component  | Type        | Image                                  |
|------------|-------------|----------------------------------------|
| demo       | Deployment  | `otel-springboot-demo:local` (built from this repo) |
| otel-collector | Deployment | `otel/opentelemetry-collector-contrib:0.103.0` |
| grafana    | Deployment  | `grafana/grafana:11.1.0`               |
| prometheus | StatefulSet | `prom/prometheus:v2.53.0`              |
| jaeger     | StatefulSet | `jaegertracing/all-in-one:1.57`        |
| loki       | StatefulSet | `grafana/loki:3.0.0`                   |
| promtail   | DaemonSet   | `grafana/promtail:3.0.0`               |

## Prerequisites

| Tool    | Why                                    |
|---------|----------------------------------------|
| minikube | local Kubernetes                      |
| kubectl  | cluster interaction                   |
| helm     | chart install                          |
| mvn      | build the demo jar                     |
| docker   | build the demo image into Minikube     |
| yq (optional) | edit values if you go off-spec    |

Resource minimum: 6 CPU, 8 GiB RAM (the demo app + collector + the three
statefulset backends all run on one node).

## Installation

From the repo root, with the worktree checked out on
`feature/minikube-otel-cluster`:

```bash
./scripts/minikube-up.sh
```

This will:

1. `minikube start --cpus=6 --memory=8192` (reuses existing cluster if up)
2. `mvn clean package` and `docker build -t otel-springboot-demo:local .`
3. `helm lint` the chart
4. `helm upgrade --install otel-observability helm/otel-observability -n observability -f values-minikube.yaml`
5. Wait for every workload Pod to be Ready
6. Print each service's NodePort URL

## Service URLs

After `minikube-up.sh` finishes, the script prints lines like:

```
  demo        http://192.168.49.2:30080
  grafana     http://192.168.49.2:30000
  prometheus  http://192.168.49.2:30090
  jaeger      http://192.168.49.2:30686
  loki        http://192.168.49.2:30310
```

If you lose them, re-run `minikube service <name> -n observability --url`.

## PromQL examples

```promql
# HTTP request rate
sum(rate(http_server_requests_seconds_count[1m]))

# 5xx rate
sum(rate(http_server_requests_seconds_count{status=~"5.."}[1m]))

# P95 latency
histogram_quantile(0.95, sum(rate(http_server_requests_seconds_bucket[5m])) by (le))

# Custom demo counter
sum(rate(demo_orders_total[1m]))

# JVM memory per area
sum(jvm_memory_used_bytes) by (area)

# Live JVM thread count
sum(jvm_threads_live_threads) by (area)
```

## LogQL examples

```logql
# All demo logs
{namespace="observability", app="otel-springboot-demo"}

# Only errors (when the demo emits structured severity)
{namespace="observability", app="otel-springboot-demo"} |= "ERROR"
```

## PVC / retention behavior

| PVC             | Size | Default retention              |
|-----------------|------|--------------------------------|
| `prometheus-data` | 5Gi | 7 days (`--storage.tsdb.retention.time`) |
| `jaeger-data`   | 5Gi  | 7 days (Badger local store)     |
| `loki-data`     | 5Gi  | 7 days (filesystem schema)     |
| `grafana-data`  | 1Gi  | persistent dashboards / users  |

The chart honors `.Values.persistence.enabled` (default `true` via
`values-minikube.yaml`). Set it to `false` to fall back to emptyDir.

## Compatibility

| Layer           | Version                                  |
|-----------------|------------------------------------------|
| Java            | 8                                        |
| Spring Boot     | 2.7.18                                   |
| Kubernetes      | 1.31 (kind / Minikube default)           |
| Helm            | 3.x                                      |
| Container runtime | both Docker and containerd (Minikube default) |

The chart uses `hostPath` for Promtail logs. The runtime is detected via
`promtail.containerLogsDir` in values — set to `/var/lib/docker/containers`
for Docker, leave the default (`/var/log/pods`) for containerd.

## Common diagnostics

```bash
# Are all pods Ready?
kubectl get pods -n observability

# Tail the demo app
kubectl logs -n observability -l app.kubernetes.io/component=app -f

# Check the collector for dropped spans
kubectl logs -n observability -l app.kubernetes.io/component=otel-collector --tail=200 | grep -i 'drop\|reject\|error'

# Recent cluster events
kubectl get events -n observability --sort-by=.lastTimestamp | tail -20

# Port-forward a service manually
kubectl port-forward -n observability svc/prometheus 9090:9090
```

## Verification

Run `scripts/verify-observability.sh` after `scripts/minikube-up.sh` to
end-to-end-check the stack. The script exits non-zero on any failure.

To tear down without losing Minikube or PVCs:

```bash
./scripts/minikube-down.sh
```

To also delete the PVCs (data loss):

```bash
./scripts/minikube-down.sh --delete-data
```
