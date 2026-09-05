# Audit Report — Untracked Files vs Plan Spec

> **Date:** 2026-09-04
> **Branch:** `feature/minikube-otel-cluster` worktree
> **Scope:** Every untracked file vs the requirements in `docs/superpowers/plans/2026-08-02-minikube-opentelemetry-implementation.md` Tasks 5 and 6.
> **Goal of this report:** Identify what each draft already satisfies, what is missing, and what is wrong — **without making any edits**.

---

## Legend

| Symbol | Meaning |
|---|---|
| ✅ | Satisfies plan requirement |
| 🟡 | Partial / minor mismatch / worth a closer look |
| ❌ | Does not satisfy / wrong / missing |
| ➕ | Draft adds something not required (fine, but flag for review) |

---

## Task 5 — Promtail + Grafana provisioning

### 5.1 `helm/otel-observability/templates/promtail-daemonset.yaml` (96 lines, 3280 bytes)

**Plan requires:**
- ✅ Mount `/var/log/pods` (read-only)
- ✅ Mount `/var/log/containers` (read-only)
- ✅ Position file mounted
- ✅ Parse Kubernetes metadata
- ✅ Send only low-cardinality labels (`namespace`, `pod`, `container`, `app`)
- ✅ Readiness probe present
- ✅ `promtail.enabled` gate

**Bonus present (not required):**
- ➕ ServiceAccount `promtail` + ClusterRole + ClusterRoleBinding (correct, RBAC needed for `role: pod`)
- ➕ HTTP listen port 9080 + container port `http`

**Issues to flag:**
- 🟡 The `containers` hostPath is hardcoded to `/var/lib/docker/containers` (line 60, 72). For `containerd`/`cri-dockerd` setups this should be parameterised. Plan said "Docker/containerd position file" — current code only handles Docker.
- 🟡 The `prometheus.io/scrape: true` annotation is missing — not required by plan but commonly added.
- 🟡 Resource limits/requests are parameterised (good) but no defaults visible — check `values-minikube.yaml`.

**Verdict:** Ready to commit after fixing the Docker/containerd path parameterisation.

---

### 5.2 `helm/otel-observability/templates/grafana-configmaps.yaml` (49 lines, 1394 bytes)

**Plan requires:**
- ✅ Prometheus as default data source (`isDefault: true`)
- ✅ Jaeger as tracing data source
- ✅ Loki as logs data source
- ✅ Trace-to-logs link with `traceID`/`trace_id` tags, `filterByTraceID: true`
- ✅ Log-to-trace derived fields with `matcherRegex` for trace IDs

**Bonus present:**
- ➕ Dashboards provider config (line 37–46) provisioning a folder `OpenTelemetry`
- ➕ Inline embedding of `dashboards/otel-demo-dashboard.json` via `.Files.Get`

**Issues to flag:**
- 🟡 One ConfigMap holds both `datasources.yaml` and `dashboards.yaml` AND `dashboard.json` — the original plan separated them as "grafana-configmaps.yaml" (plural) but the structure inside is the same.
- 🟡 Dashboard file is read at template-render time via `.Files.Get "dashboards/..."`. If `dashboards/` is missing or moved, render fails. Acceptable, but the error message will be cryptic.

**Verdict:** Ready to commit.

---

### 5.3 `helm/otel-observability/templates/grafana-deployment.yaml` (41 lines, 2123 bytes)

**Plan requires:**
- ✅ Dashboard provisioning (request rate, 5xx rate, P95 latency, JVM memory/thread panels, custom demo metrics, Collector health, Loki logs)
- ✅ Service variable defaulting to `otel-springboot-demo`
- ✅ 1Gi PVC for Grafana state (conditional)
- ✅ NodePort / optional Ingress exposure (handled in service)

**Issues to flag:**
- 🟡 **Dashboard mount path mismatch**: deployment mounts `dashboard.json` to `/var/lib/grafana/dashboards/otel-demo-dashboard.json` with `subPath: dashboard.json`. The ConfigMap provider config (line 46 in grafana-configmaps.yaml) declares `path: /var/lib/grafana/dashboards` — so Grafana will scan `/var/lib/grafana/dashboards/otel-demo-dashboard.json`. Subpath works, but is awkward.
- 🟡 No JVM **thread** panel in dashboard (plan says "JVM memory/thread panels"). Dashboard only has `jvm_memory_used_bytes`.
- 🟡 Grafana PVC size (1Gi) not parameterised — hardcoded missing.

**Verdict:** Needs work — JVM thread panel + PVC size parameterisation.

---

### 5.4 `helm/otel-observability/templates/grafana-service.yaml` (15 lines, 444 bytes)

**Plan requires:**
- ✅ NodePort / optional Ingress support

**Issues to flag:** None.

**Verdict:** Ready to commit.

---

### 5.5 `helm/otel-observability/templates/ingress.yaml` (18 lines, 1066 bytes)

**Plan requires:**
- ✅ Ingress exposes grafana, prometheus, jaeger, demo

**Issues to flag:**
- 🟡 Loki not exposed via ingress (plan didn't require it, but is usually desired). Acceptable as-is.
- 🟡 Only `tls` config is missing — plan didn't require TLS for local Minikube, so acceptable.

**Verdict:** Ready to commit.

---

### 5.6 `helm/otel-observability/dashboards/otel-demo-dashboard.json` (20 lines, 1549 bytes)

**Plan requires:**
- ✅ Request rate panel (panel 1: `rate(http_server_requests_seconds_count[1m])`)
- ✅ 5xx rate panel (panel 2: `rate(http_server_requests_seconds_count{status=~"5.."}[1m])`)
- ✅ P95 latency panel (panel 3: `histogram_quantile`)
- ✅ JVM memory panel (panel 5: `jvm_memory_used_bytes by (area)`)
- ✅ Custom OTel Orders panel (panel 4: `rate(demo_orders_total[1m])`)
- ✅ Collector health panel (panel 6: `up`)
- ✅ Application Logs panel (panel 7: Loki with hardcoded `otel-springboot-demo` filter)
- ✅ Service variable defaulting to `otel-springboot-demo` (templating.list[0])

**Issues to flag:**
- 🟡 Service variable `service` exists but **panels don't reference `$service`** — Loki query is hardcoded `{namespace="observability", app="otel-springboot-demo"}`. Plan said "service variable defaulting to otel-springboot-demo" — implying it should be usable. Minor.
- 🟡 No **JVM thread** panel — plan required "JVM memory/thread panels".
- 🟡 Dashboard `uid` is `otel-springboot-demo` — same as service name. Plan allowed this; ok.

**Verdict:** Needs work — JVM thread panel + use `$service` in panels (or remove the variable).

---

### 5.7 `tests/helm/test_grafana.sh` (18 lines, 690 bytes)

**Plan requires:**
- ✅ Render with `helm template ... -f values-minikube.yaml`
- ✅ Assert presence of Promtail DaemonSet
- ✅ Assert Grafana ConfigMap presence (via data source name grep)
- ✅ Assert all four data sources are provisioned (Prometheus, Jaeger, Loki + dashboard)
- ✅ Exit non-zero on any miss

**Issues to flag:**
- 🟡 Hardcoded port numbers `9090` / `16686` / `3100` will break if `values-minikube.yaml` changes ports.
- 🟡 Test greps for `name: Prometheus` etc. — if anyone renames a data source, test fails. Brittle but acceptable.
- 🟡 Missing assertion for **4 low-cardinality labels only** in Promtail relabeling (plan Step 5 said "verify only allowed labels sent").

**Verdict:** Mostly ready; minor port-coupling concern + missing label cardinality check.

---

## Task 6 — Minikube lifecycle + verification

### 6.1 `scripts/minikube-up.sh` (24 lines, 1366 bytes)

**Plan requires:**
- ✅ `--help`
- ✅ Missing/unknown command diagnostics
- ✅ `minikube start --cpus=6 --memory=8192`
- ✅ `eval "$(minikube docker-env)"`
- ✅ `mvn clean package`
- ✅ `docker build -t otel-springboot-demo:local`
- ✅ `helm lint`
- ✅ `helm upgrade --install --create-namespace -n observability`
- ✅ `kubectl rollout status`
- ✅ `minikube service ... --url` output

**Issues to flag:**
- 🟡 Line 21: `kubectl rollout status deployment/otel-observability-otel-observability-app` — chart name is `otel-observability`, app is presumably a different label. **Verify this matches actual rendered Deployment name.** Likely wrong — typical Helm naming is `RELEASE-CHART-app` which gives `otel-observability-otel-observability-app`. Need to confirm against the rendered chart.
- 🟡 `kubectl rollout status` only covers 3 Deployments. **StatefulSets (prometheus/jaeger/loki) and DaemonSet (promtail) are not rolled out checked.** Use `kubectl wait --for=condition=Ready pod -l ...` for those.
- 🟡 Line 24: `minikube service ... --url` loops demo/grafana/prometheus/jaeger but **missing loki**.
- 🟡 No `--values-file` flag override — cannot point at `values-prod.yaml` if it ever exists. Minor.
- 🟡 No trap for cleanup on failure — if `helm install` fails, you may leave Minikube running. Add `trap "echo 'minikube-up.sh failed — leaving minikube running for debugging'" EXIT`.

**Verdict:** Needs work — fix Deployment name, add StatefulSet/DaemonSet readiness, add loki to service URLs.

---

### 6.2 `scripts/minikube-down.sh` (13 lines, 532 bytes)

**Plan requires:**
- ✅ `--help`
- ✅ `--delete-data` flag
- ✅ Default safe teardown (no PVC delete)
- ✅ Helm uninstall
- ✅ PVC deletion only with `--delete-data`
- ✅ Never stop/delete unrelated Minikube profiles

**Issues to flag:**
- 🟡 Code never calls `minikube stop` or `minikube delete` — so "never delete unrelated profiles" is trivially satisfied. Acceptable.
- 🟡 No confirmation prompt before PVC deletion. Plan didn't require it; acceptable.

**Verdict:** Ready to commit.

---

### 6.3 `scripts/verify-observability.sh` (21 lines, 1379 bytes)

**Plan requires:**
- ✅ Wait for all workloads Ready (uses `kubectl wait --for=condition=available deployment --all`)
- ✅ `/api/hello`, `/api/orders/1001`, `/api/load?count=50`, `/api/error`
- ✅ Query Prometheus for `up`, `demo_orders_total`, `demo_errors_total`, `http_server_requests_seconds_count`
- ✅ Grafana data sources provisioned
- ✅ Exit non-zero on any failure

**Issues to flag:**
- ❌ **No Jaeger query** — plan required "Query Jaeger for `otel-springboot-demo`".
- ❌ **No Loki query** — plan required "Query Loki for `{namespace="observability", app="otel-springboot-demo"}`".
- 🟡 Line 14: `prometheus_url="http://prometheus:9090"` is in-cluster DNS — **won't work from host shell**. Use `minikube service prometheus --url` like Grafana URLs.
- 🟡 `kubectl wait --for=condition=available deployment --all` does **not** cover StatefulSets (prometheus/jaeger/loki) or DaemonSet (promtail). Need `kubectl wait --for=condition=Ready pod -l ... --all`.
- 🟡 Grafana datasource checks use raw URLs (`/api/datasources/name/Prometheus`) — fine but assumes anonymous auth, which works only because `GF_USERS_ALLOW_SIGN_UP=false` and default admin is set. Acceptable for verification.

**Verdict:** **Needs significant work** — add Jaeger + Loki queries, fix Prometheus URL to use minikube service, extend wait to cover all workload kinds.

---

### 6.4 `helm/otel-observability/README.md` (6 lines, 323 bytes)

**Plan requires:**
- 🟡 "Document values, dependencies, and upgrade semantics" — current is too brief.
- 🟡 Plan also said (in Task 6 Step 5): "prerequisites, resource requirements, installation, URLs, PromQL, LogQL, PVC/retention behavior, compatibility, common `kubectl` diagnostics, and expected verification output" — **none of those sections exist**.

**Issues to flag:**
- ❌ Missing: values documentation, prerequisites, URLs, troubleshooting, verification output samples.

**Verdict:** **Needs significant work** — expand to cover all required sections.

---

### 6.5 `tests/integration/README.md` (6 lines, 287 bytes)

**Plan requires:**
- 🟡 "Explain how to run verify-observability.sh against a live Minikube" — current is minimal but covers the essentials.

**Issues to flag:**
- ❌ No troubleshooting section (failed checks, common errors).
- ❌ No expected output sample.

**Verdict:** Needs expansion — but less severe than helm README.

---

### 6.6 `tests/scripts/test_minikube_scripts.sh` (6 lines, 401 bytes)

**Plan requires (Task 6 Step 1):**
- ✅ `--help` for each script
- ✅ Missing/unknown command diagnostics
- 🟡 "Safe default teardown" — script doesn't test that `minikube-down.sh` without `--delete-data` leaves PVCs alone. Should add a test that runs uninstall without the flag and asserts PVCs remain.
- 🟡 "Data deletion requires `--delete-data`" — script doesn't test this either. Should test that with `--delete-data`, PVCs would be deleted (mock or skip if minikube not present).

**Bonus present:**
- ➕ Tests `--unexpected` flag rejection (line 5–6) — good.

**Verdict:** Needs work — add safe-teardown + `--delete-data` behavior tests.

---

## Summary Verdict

| File | Ready to commit? | Blocking issues |
|---|---|---|
| `promtail-daemonset.yaml` | 🟡 mostly | Docker/containerd path hardcoded |
| `grafana-configmaps.yaml` | ✅ yes | — |
| `grafana-deployment.yaml` | 🟡 no | JVM thread panel missing; PVC size hardcoded |
| `grafana-service.yaml` | ✅ yes | — |
| `ingress.yaml` | ✅ yes | — |
| `dashboards/otel-demo-dashboard.json` | 🟡 no | JVM thread panel missing; `$service` unused |
| `tests/helm/test_grafana.sh` | 🟡 mostly | Hardcoded ports; missing label cardinality check |
| `scripts/minikube-up.sh` | 🟡 no | Wrong deployment name likely; missing StatefulSet/DaemonSet readiness; missing loki URL |
| `scripts/minikube-down.sh` | ✅ yes | — |
| `scripts/verify-observability.sh` | ❌ no | Missing Jaeger + Loki queries; wrong Prometheus URL; missing non-Deployment workload waits |
| `helm/otel-observability/README.md` | ❌ no | Almost entirely missing |
| `tests/integration/README.md` | 🟡 mostly | Missing troubleshooting/output samples |
| `tests/scripts/test_minikube_scripts.sh` | 🟡 mostly | Missing safe-teardown + `--delete-data` behaviour tests |

---

## Aggregated Issues — Top Priority

When you're ready to commit Tasks 5 and 6, these are the blockers that **must** be addressed first:

1. **`verify-observability.sh`** is the most broken: missing Jaeger/Loki queries, uses in-cluster URL for Prometheus, doesn't wait on StatefulSets/DaemonSet. Plan requirement gap is large.
2. **`minikube-up.sh`** deployment name `otel-observability-otel-observability-app` needs verification against the rendered chart (line 21). Likely wrong.
3. **`grafana-deployment.yaml` + `dashboard.json`** missing JVM thread panel.
4. **`helm/otel-observability/README.md`** is essentially absent of plan content.
5. **`promtail-daemonset.yaml`** containerd path not parameterised.

The rest are minor (port coupling, dashboard variable usage, test depth).

## Non-Blocking Observations

- Grafana state PVC size 1Gi is not parameterised — small concern but doesn't affect correctness.
- Promtail hardcoded to `/var/lib/docker/containers` — won't work on `containerd`-based Minikube (default since 1.24+).
- `tests/helm/test_grafana.sh` greps for hardcoded labels — brittle to label rename, acceptable.

## What Was Not Audited

The plan requires updates to top-level `README.md`. There is no untracked `README.md`, so I assume the existing `README.md` is what will be modified. **I did not audit `README.md`** — it's a tracked file and presumably correct as-is. Verify separately before committing.
