# Minikube OpenTelemetry Local Cluster Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement and verify the self-contained Helm deployment described in the approved design for a Java 8 / Spring Boot 2.7 OpenTelemetry demo on Minikube.

**Architecture:** Build one Umbrella Chart containing the demo, Collector, Prometheus, Grafana, Jaeger, Loki, and Promtail. Use OTLP for application telemetry, Kubernetes stdout logs for Promtail, PVC-backed local storage, and Grafana provisioning for cross-signal navigation.

**Tech Stack:** Java 8, Spring Boot 2.7.18, Maven, OpenTelemetry Java Agent, Docker, Kubernetes, Minikube, Helm, OpenTelemetry Collector Contrib, Prometheus, Grafana, Jaeger, Loki, Promtail.

## Global Constraints

- Final local deployment entry point is Helm on Minikube; Docker Compose remains reference-only.
- Preserve Java 8 and Spring Boot 2.7.18 compatibility.
- Default namespace is `observability`.
- Default storage uses Minikube `standard` StorageClass and PVCs.
- Keep metric and log labels low-cardinality; never index order IDs or request IDs.
- Pin component image and Java Agent versions in values and validate rendered configuration.
- Do not add Kubernetes Operators, production HA, or an offline registry.

---

### Task 1: Isolate the implementation workspace and establish chart/test scaffolding

**Files:**
- Modify: `.gitignore`
- Create: `docs/superpowers/plans/2026-08-02-minikube-opentelemetry-implementation.md`
- Create: `helm/otel-observability/Chart.yaml`
- Create: `helm/otel-observability/values.yaml`
- Create: `helm/otel-observability/values-minikube.yaml`
- Create: `helm/otel-observability/templates/_helpers.tpl`
- Create: `tests/helm/test_render.sh`

**Interfaces:**
- Produces Helm release name `otel-observability`, namespace `observability`, and values keys consumed by all later templates.

- [ ] **Step 1: Verify the current checkout is not already a linked worktree.**

Run:

```bash
git rev-parse --git-dir
git rev-parse --git-common-dir
git branch --show-current
git status --short
```

Expected: current `main` checkout, clean status, and equal git/common directories.

- [ ] **Step 2: Add `.worktrees/` to `.gitignore`, commit it on `main`, and create a feature worktree.**

Use branch `feature/minikube-otel-cluster` and path `.worktrees/minikube-otel-cluster`; verify the directory is ignored before creation.

- [ ] **Step 3: Add the Chart metadata and values contract.**

`Chart.yaml` must declare chart name `otel-observability`, type `application`, and an explicit chart version. `values.yaml` must define image repositories/tags, namespace, service types, NodePorts, storage sizes, retention periods, resource requests/limits, probes, and component enable flags. `values-minikube.yaml` must set local image pull policy to `IfNotPresent`, low-resource limits, and the demo image to `otel-springboot-demo:local`.

- [ ] **Step 4: Add Helm helper functions and a render smoke test.**

The test must run `helm lint` and `helm template` with `values-minikube.yaml`, then assert the rendered output contains the `observability` namespace, all seven component workload names, OTLP ports `4317` and `4318`, and PVC declarations.

- [ ] **Step 5: Run the scaffolding verification.**

Run:

```bash
helm lint helm/otel-observability
bash tests/helm/test_render.sh
```

Expected: lint and render checks pass.

- [ ] **Step 6: Commit the scaffolding.**

```bash
git add .gitignore helm tests/helm/test_render.sh docs/superpowers/plans/2026-08-02-minikube-opentelemetry-implementation.md
git commit -m "build: scaffold minikube observability helm chart"
```

### Task 2: Make the Java 8 Spring Boot demo container-ready

**Files:**
- Modify: `Dockerfile`
- Modify: `docker-compose.yml` only when shared image/version defaults need alignment
- Modify: `src/main/resources/application.yml`
- Modify: `src/main/java/com/example/otel/DemoController.java` only for missing testability or logging behavior
- Create: `helm/otel-observability/templates/app-deployment.yaml`
- Create: `helm/otel-observability/templates/app-service.yaml`
- Create: `src/test/java/com/example/otel/DemoControllerTest.java`

**Interfaces:**
- Consumes chart image and `otelCollector.service.name` values.
- Produces Service `demo`, container port `8080`, health endpoints, stdout logs, and OTel environment variables.

- [ ] **Step 1: Add failing MVC tests for the demo endpoints and error behavior.**

Use `@WebMvcTest(DemoController.class)` to assert `/api/hello` returns 200, `/api/orders/1001` returns the requested ID, `/api/load?count=3` caps and reports the generated count, and `/api/error` returns 500.

- [ ] **Step 2: Run the focused tests and confirm the expected baseline.**

```bash
mvn -Dtest=DemoControllerTest test
```

- [ ] **Step 3: Add container-safe logging and configurable service metadata.**

Keep logs on stdout, preserve low-cardinality custom metric attributes, and expose `server.port`, service name, environment, and version through Spring properties used by the deployment template.

- [ ] **Step 4: Update the Dockerfile for a reproducible Java 8 image.**

Use a Java 8 JRE base, pin the Agent version through `ARG`, copy the built jar and agent to stable paths, and launch with `JAVA_TOOL_OPTIONS` supplied by Kubernetes. Do not bake cluster hostnames into the image.

- [ ] **Step 5: Add the app Deployment and Service template.**

Configure `imagePullPolicy: IfNotPresent`, port 8080, `/actuator/health` readiness/liveness probes, `OTEL_SERVICE_NAME`, resource attributes, OTLP gRPC endpoint, exporter selections, and `OTEL_METRIC_EXPORT_INTERVAL`. Use a Service named `demo`.

- [ ] **Step 6: Run Java and Helm checks.**

```bash
mvn test
helm lint helm/otel-observability
helm template otel-observability helm/otel-observability -f helm/otel-observability/values-minikube.yaml
```

- [ ] **Step 7: Commit the Demo container integration.**

```bash
git add Dockerfile src/main src/test helm/otel-observability/templates/app-*.yaml
git commit -m "feat: containerize spring boot otel demo for minikube"
```

### Task 3: Implement Collector pipelines and backend Services

**Files:**
- Create: `helm/otel-observability/templates/collector-configmap.yaml`
- Create: `helm/otel-observability/templates/collector-deployment.yaml`
- Create: `helm/otel-observability/templates/collector-service.yaml`
- Create: `tests/helm/test_collector_config.sh`

**Interfaces:**
- Consumes backend Service DNS names and ports from values.
- Produces OTLP gRPC/HTTP receivers and internal Prometheus exporter endpoint `8889`.

- [ ] **Step 1: Define the Collector config test assertions.**

The test must verify rendered YAML contains `otlp` gRPC and HTTP receivers, `memory_limiter`, `resource`, `batch`, retry/queue settings, and three pipelines named `traces`, `metrics`, and `logs`; it must also reject order/request IDs as metric or Loki labels.

- [ ] **Step 2: Implement Collector configuration.**

Use OTLP receivers on `0.0.0.0:4317` and `0.0.0.0:4318`; set resource attributes for service version, environment, and Kubernetes namespace; export metrics through a Prometheus exporter on `8889`, traces to Jaeger OTLP, and logs to Loki using the selected contrib exporter. Configure batch, memory limiter, retry, and sending queue per pipeline.

- [ ] **Step 3: Implement Collector Deployment and Service.**

Add config checksum annotation, non-root security context where supported, CPU/memory resources, readiness/liveness probes, ports 4317/4318/8889, and a ClusterIP Service named `otel-collector`.

- [ ] **Step 4: Run config and render tests.**

```bash
bash tests/helm/test_collector_config.sh
helm lint helm/otel-observability
```

- [ ] **Step 5: Commit the Collector pipeline.**

```bash
git add helm/otel-observability/templates/collector-* tests/helm/test_collector_config.sh
git commit -m "feat: add otel collector pipelines"
```

### Task 4: Add persistent Prometheus, Jaeger, and Loki storage

**Files:**
- Create: `helm/otel-observability/templates/prometheus-configmap.yaml`
- Create: `helm/otel-observability/templates/prometheus-rules-configmap.yaml`
- Create: `helm/otel-observability/templates/prometheus-statefulset.yaml`
- Create: `helm/otel-observability/templates/prometheus-service.yaml`
- Create: `helm/otel-observability/templates/jaeger-statefulset.yaml`
- Create: `helm/otel-observability/templates/jaeger-service.yaml`
- Create: `helm/otel-observability/templates/loki-statefulset.yaml`
- Create: `helm/otel-observability/templates/loki-service.yaml`
- Create: `helm/otel-observability/templates/pvc.yaml`
- Create: `tests/helm/test_storage.sh`

**Interfaces:**
- Produces stable Services `prometheus`, `jaeger`, and `loki`, plus PVC-backed storage consumed by Collector and Grafana.

- [ ] **Step 1: Add Prometheus scrape config and rules.**

Scrape Collector `8889` and Demo `/actuator/prometheus` on `8080` every 5 seconds. Add recording rules for request rate, 5xx rate, P95 latency, order rate, and Collector receive/drop volume. Add alerts for Demo/Collector unavailable, high 5xx/P95, exporter failure, and target down.

- [ ] **Step 2: Implement Prometheus StatefulSet and PVC.**

Mount the config, rules, and `/prometheus` PVC; set `--storage.tsdb.retention.time=7d`, probes, resource limits, and Service port 9090.

- [ ] **Step 3: Implement Jaeger storage.**

Use a pinned Jaeger all-in-one image with local Badger storage on a 5Gi PVC, expose UI and OTLP receiver ports through a ClusterIP Service, configure 7-day retention where supported, and add probes.

- [ ] **Step 4: Implement Loki storage.**

Use a pinned Loki single-binary image with filesystem storage on a 5Gi PVC, configure the local schema and 7-day retention, expose HTTP on port 3100, and add probes.

- [ ] **Step 5: Add storage render tests.**

Verify StatefulSets mount PVCs, Prometheus rules contain all required recording/alert names, and rendered Services expose the expected ports.

- [ ] **Step 6: Run storage checks and commit.**

```bash
bash tests/helm/test_storage.sh
helm template otel-observability helm/otel-observability -f helm/otel-observability/values-minikube.yaml
git add helm/otel-observability/templates/{prometheus*,jaeger*,loki*,pvc.yaml} tests/helm/test_storage.sh
git commit -m "feat: add persistent metrics trace and log backends"
```

### Task 5: Add Promtail and Grafana provisioning

**Files:**
- Create: `helm/otel-observability/templates/promtail-daemonset.yaml`
- Create: `helm/otel-observability/templates/grafana-configmaps.yaml`
- Create: `helm/otel-observability/templates/grafana-deployment.yaml`
- Create: `helm/otel-observability/templates/grafana-service.yaml`
- Create: `helm/otel-observability/templates/ingress.yaml`
- Modify: `grafana/dashboards/otel-demo-dashboard.json`
- Create: `tests/helm/test_grafana.sh`

**Interfaces:**
- Promtail sends node container logs to `http://loki:3100/loki/api/v1/push`.
- Grafana consumes `prometheus:9090`, `jaeger:16686`, and `loki:3100`.

- [ ] **Step 1: Implement Promtail DaemonSet.**

Mount `/var/log/pods`, `/var/log/containers`, and the Docker/containerd position file as read-only where appropriate; parse Kubernetes metadata; send only low-cardinality labels (`namespace`, `pod`, `container`, `app`) to Loki; configure readiness and a `promtail.enabled` gate.

- [ ] **Step 2: Implement Grafana data source provisioning.**

Provision Prometheus as the default data source, Jaeger as a tracing data source, and Loki as a logs data source. Configure trace-to-logs using `traceID`/`trace_id` fields and log-to-trace links where the stored log format contains a trace ID.

- [ ] **Step 3: Implement Dashboard provisioning and Grafana PVC.**

Provision a Dashboard with request rate, 5xx rate, P95 latency, JVM memory/thread panels, custom demo metrics, Collector health, Loki logs, and a service variable defaulting to `otel-springboot-demo`. Store Grafana state on a 1Gi PVC and expose NodePort/optional Ingress.

- [ ] **Step 4: Add provisioning tests and commit.**

```bash
bash tests/helm/test_grafana.sh
helm lint helm/otel-observability
git add helm/otel-observability/templates/{promtail*,grafana*,ingress.yaml} grafana tests/helm/test_grafana.sh
git commit -m "feat: provision grafana logs and traces"
```

### Task 6: Add Minikube lifecycle and end-to-end verification

**Files:**
- Create: `scripts/minikube-up.sh`
- Create: `scripts/minikube-down.sh`
- Create: `scripts/verify-observability.sh`
- Modify: `README.md`
- Create: `helm/otel-observability/README.md`
- Create: `tests/integration/README.md`

**Interfaces:**
- `minikube-up.sh` builds `otel-springboot-demo:local`, installs/upgrades the Chart, and prints service URLs.
- `minikube-down.sh` uninstalls the release and optionally deletes PVCs with explicit `--delete-data`.
- `verify-observability.sh` exits non-zero on any failed readiness, HTTP, Prometheus, Jaeger, Loki, or Grafana check.

- [ ] **Step 1: Write script usage tests.**

Check `--help`, missing-command diagnostics, safe default teardown, and that data deletion requires `--delete-data`.

- [ ] **Step 2: Implement `minikube-up.sh`.**

Use `minikube start --cpus=6 --memory=8192`, `eval "$(minikube docker-env)"`, `mvn clean package`, local image build, `helm lint`, `helm upgrade --install --create-namespace -n observability`, `kubectl rollout status`, and `minikube service ... --url` output.

- [ ] **Step 3: Implement `minikube-down.sh`.**

Uninstall only the named release by default; delete PVCs only when `--delete-data` is explicitly supplied; never stop/delete unrelated Minikube profiles.

- [ ] **Step 4: Implement the verification script.**

Wait for all workloads, call `/api/hello`, `/api/orders/1001`, `/api/load?count=50`, and `/api/error`; query Prometheus for `up`, `demo_orders_total`, `demo_errors_total`, and `http_server_requests_seconds_count`; query Jaeger for `otel-springboot-demo`; query Loki for `{namespace="observability", app="otel-springboot-demo"}`; assert Grafana data sources are provisioned.

- [ ] **Step 5: Document deployment and troubleshooting.**

Document prerequisites, resource requirements, installation, URLs, PromQL, LogQL, PVC/retention behavior, compatibility, common `kubectl` diagnostics, and expected verification output.

- [ ] **Step 6: Run the full local verification and commit.**

```bash
mvn test
helm lint helm/otel-observability
bash tests/helm/test_render.sh
bash tests/helm/test_collector_config.sh
bash tests/helm/test_storage.sh
bash tests/helm/test_grafana.sh
./scripts/minikube-up.sh
./scripts/verify-observability.sh
```

Commit:

```bash
git add scripts README.md helm/otel-observability/README.md tests
git commit -m "test: add minikube observability verification"
```

### Task 7: Final verification and branch handoff

**Files:**
- Modify: any files required by verification failures only

- [ ] **Step 1: Run the complete test suite and inspect all rendered manifests.**

Run Maven tests, every Helm shell test, `helm lint`, and the Minikube integration verification. Save command output summaries in the handoff, not generated cluster state in Git.

- [ ] **Step 2: Test persistence recovery.**

Restart Demo, Collector, Prometheus, Jaeger, and Loki Pods and rerun the signal queries; verify data remains available from PVC-backed stores.

- [ ] **Step 3: Check the working tree and commits.**

```bash
git status --short
git log --oneline --decorate -8
```

Expected: no uncommitted files except intentional user changes, and one focused commit per completed task.

- [ ] **Step 4: Hand off to `superpowers:finishing-a-development-branch`.**

Present test evidence and integration options only after all required checks pass.
