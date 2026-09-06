# Minikube integration verification

The scripts in `scripts/` drive a real Minikube deployment and check the
resulting observability stack end-to-end. This document explains what they
verify, how to run them, and how to interpret common failures.

## What `verify-observability.sh` checks

The script exits non-zero on any failure. Each step prints `ok: <step>`
when it passes.

| Check                                  | What it catches                                       |
|----------------------------------------|-------------------------------------------------------|
| All Pods Ready                         | CrashLoopBackOff, image pull errors, pending probes  |
| Service URLs resolvable                | helm install never finished, missing NodePort          |
| `/api/hello` 200                       | Demo app not up, OTel agent crash                     |
| `/api/orders/1001` echoes ID          | Controller routing broken                             |
| `/api/load?count=50` caps at 50       | Custom metric not being scraped                      |
| `/api/error` returns 500               | Demo app error path not reached                       |
| Prometheus `up{}`                      | Targets not being scraped                             |
| Prometheus demo_orders_total           | Custom metric missing                                 |
| Prometheus demo_errors_total           | Custom error metric missing                            |
| Prometheus http_server_requests_*     | Spring Boot Actuator metrics missing                  |
| Jaeger `/api/services` lists demo     | Collector not exporting traces, or TLS wrong          |
| Loki `query_range` for demo logs      | Promtail not scraping, or Loki store not started     |
| Grafana datasource `Prometheus`        | Data source provisioning failed                      |
| Grafana datasource `Jaeger`            | Data source provisioning failed                      |
| Grafana datasource `Loki`              | Data source provisioning failed                      |

## Running it

From the worktree:

```bash
./scripts/minikube-up.sh
./scripts/verify-observability.sh
```

Or step by step to debug a failure:

```bash
./scripts/verify-observability.sh 2>&1 | tee /tmp/verify.log
```

To adjust the timeout (default 180s per pod readiness wait):

```bash
VERIFY_TIMEOUT=300 ./scripts/verify-observability.sh
```

## Common failures and what they mean

### `could not resolve <service> service URL`

`minikube service` returned no URL. Likely cause: the Helm install did not
finish, or the Service was deleted. Run:

```bash
kubectl get svc -n observability
kubectl get helm list -n observability
```

If the release is missing, `helm list -n observability` returns nothing —
re-run `scripts/minikube-up.sh`.

### `pods not Ready in 180s`

A workload failed to start. Common causes:

- **ImagePullBackOff**: the local image was not built into Minikube's Docker
  daemon. Verify by running `eval "$(minikube docker-env)" && docker images`
  inside the same shell that runs `minikube-up.sh`.
- **CrashLoopBackOff**: read `kubectl logs -n observability <pod>`.
- **Pending**: not enough CPU/memory in Minikube. Check `minikube status`.

### `/api/echo 500` instead of 200

The demo app started but errored. Check:

```bash
kubectl logs -n observability -l app.kubernetes.io/component=app --tail=50
```

Often the OTel agent failed to attach (missing `opentelemetry-javaagent.jar`)
or the collector endpoint is wrong.

### Jaeger lists 0 services

The collector is not exporting traces to Jaeger. Check:

```bash
kubectl logs -n observability -l app.kubernetes.io/component=otel-collector --tail=50
```

Look for `Failed to connect to Jaeger` or `export timeout`.

### Loki query returns `success` but empty streams

Promtail is not scraping the demo container logs. Check:

```bash
kubectl logs -n observability -l app.kubernetes.io/component=promtail --tail=50
```

Verify `promtail.containerLogsDir` in `values-minikube.yaml` matches the
runtime (containerd → `/var/log/pods`, Docker → `/var/lib/docker/containers`).

### Grafana datasource 404

The ConfigMap was not mounted, or Grafana was restarted before the volume
became available. Check:

```bash
kubectl describe deploy grafana -n observability | grep -A 5 Mounts
```

If the ConfigMap volume is missing, re-apply with
`kubectl rollout restart deploy/grafana -n observability`.

## What this script does NOT verify

- High availability / failover (single-replica by design for local dev).
- TLS / mTLS — the chart runs plain HTTP inside the cluster.
- Production-grade scrape intervals / recording rules — those are in
  `tests/helm/test_storage.sh` and `tests/helm/test_collector_config.sh`.

For full cluster bring-up, see `helm/otel-observability/README.md` in the
chart directory.
