# Minikube OpenTelemetry Local Cluster — Continue Execution Plan (v2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Context:** This plan continues from the original `2026-08-02-minikube-opentelemetry-implementation.md`. Tasks 1–4 are **done and committed** on `feature/minikube-otel-cluster`. Tasks 5–6 are **started but uncommitted** (files exist on disk). Task 7 is **not started**. Read the original plan first for the architectural context.
>
> **Scope Check:** This plan finishes a single deployment system already split into 7 sub-tasks by the original spec. No sub-spec split is required. The continuation covers the remaining 3 tasks (Tasks 5–7) without adding new functional requirements.

**Goal:** Finish Tasks 5–7 of the Minikube OpenTelemetry deployment plan — complete the uncommitted Grafana/Promtail/Minikube-lifecycle work, commit it, then hand off `feature/minikube-otel-cluster` to the user via `superpowers:finishing-a-development-branch` for review and integration options.

**Architecture:** Same as the original plan — one Umbrella Chart with the demo, Collector, Prometheus, Grafana, Jaeger, Loki, Promtail. OTLP for application telemetry, Kubernetes stdout logs for Promtail, PVC-backed local storage, Grafana provisioning for cross-signal navigation.

**Tech Stack:** Java 8, Spring Boot 2.7.18, Maven, OpenTelemetry Java Agent, Docker, Kubernetes, Minikube, Helm, OpenTelemetry Collector Contrib, Prometheus, Grafana, Jaeger, Loki, Promtail.

## Global Constraints

- Final local deployment entry point is Helm on Minikube; Docker Compose remains reference-only.
- Preserve Java 8 and Spring Boot 2.7.18 compatibility.
- Default namespace is `observability`.
- Default storage uses Minikube `standard` StorageClass and PVCs.
- Keep metric and log labels low-cardinality; never index order IDs or request IDs.
- Pin component image and Java Agent versions in values and validate rendered configuration.
- Do not add Kubernetes Operators, production HA, or an offline registry.
- **Working directory for Tasks 5–7 is the existing worktree** at `.worktrees/minikube-otel-cluster` on branch `feature/minikube-otel-cluster` — do NOT create a new worktree.
- Untracked files currently on disk (Promtail DaemonSet, Grafana templates, scripts, dashboards, tests) are **drafts to be reviewed**, not finished work — diff them against the requirements in this plan before committing.
- **Assumed Helm values keys** (already defined in Tasks 1–4 `values.yaml`): `images.<component>.repository/tag`, `prometheus.service.port`, `jaeger.service.{port,uiPort}`, `loki.service.port`, `app.service.port`, `grafana.service.{type,port,nodePort,adminUser,adminPassword,replicas,resources}`, `grafana.persistence.enabled`, `promtail.{enabled,resources}`, `ingress.{enabled,className,hostSuffix}`. **Verify these are still defined before rendering** — open `helm/otel-observability/values.yaml` and confirm. If any key is missing, fix it in the values file before continuing.
- **Dashboard location decision:** The current draft has `otel-demo-dashboard.json` at `helm/otel-observability/dashboards/` (moved from the original plan's `grafana/dashboards/`). This move is **accepted** — keeping the dashboard inside the chart makes the chart self-contained. Original `grafana/dashboards/otel-demo-dashboard.json` is left in place as reference but is no longer rendered.

---

### Task 5: Add Promtail and Grafana provisioning (FINISH)

**Status:** Files created on disk, untracked, not committed. Drafts only.

**Files (review before commit):**
- Draft, review, finalize: `helm/otel-observability/templates/promtail-daemonset.yaml`
- Draft, review, finalize: `helm/otel-observability/templates/grafana-configmaps.yaml`
- Draft, review, finalize: `helm/otel-observability/templates/grafana-deployment.yaml`
- Draft, review, finalize: `helm/otel-observability/templates/grafana-service.yaml`
- Draft, review, finalize: `helm/otel-observability/templates/ingress.yaml`
- Existing (chart-relative, accepted): `helm/otel-observability/dashboards/otel-demo-dashboard.json` — fix per audit (Step 5)
- Existing draft: `tests/helm/test_grafana.sh` — review and finalize (was Step 5, now Step 6)

**Interfaces:**
- Promtail sends node container logs to `http://loki:3100/loki/api/v1/push`.
- Grafana consumes `prometheus:9090`, `jaeger:16686`, and `loki:3100`.

- [ ] **Step 1: Verify Helm values keys used by the draft templates exist.**

  Open `helm/otel-observability/values.yaml` and confirm every key referenced in the five Grafana/Promtail templates is defined. Required keys: `images.promtail.repository/tag`, `images.grafana.repository/tag`, `grafana.{replicas,adminUser,adminPassword,resources,persistence.enabled}`, `prometheus.service.port`, `jaeger.service.uiPort`, `loki.service.port`, `grafana.service.{type,port,nodePort}`, `promtail.{enabled,resources}`, `ingress.{enabled,className,hostSuffix}`. If any is missing, add it to `values.yaml` and document in the commit message.

- [ ] **Step 2: Audit each draft against the plan spec in `docs/superpowers/plans/2026-08-02-minikube-opentelemetry-implementation.md` Task 5.**

  Cross-reference each draft with the audit report at `docs/superpowers/plans/2026-09-04-audit-report.md`. The Top 5 blockers from the audit (Promtail containerd path, JVM thread panel, deployment name checks, etc.) are listed there. Make a focused fix list; do not edit yet.

- [ ] **Step 3: Fix the Promtail DaemonSet against the spec.**

  Required (per plan Step 1 of Task 5):
  - Mount `/var/log/pods`, `/var/log/containers`, and the Docker/containerd position file as read-only where appropriate.
  - Parse Kubernetes metadata.
  - Send only low-cardinality labels (`namespace`, `pod`, `container`, `app`) to Loki.
  - Readiness probe present.
  - `promtail.enabled` gate respected.
  - **Additional fix from audit:** parameterise the Docker/containerd container log directory so the chart works on Minikube default (containerd) and on Docker. Add `promtail.containerLogsDir` to `values.yaml` (default `/var/lib/docker/containers`).

  Run:
  ```bash
  helm lint helm/otel-observability
  helm template otel-observability helm/otel-observability -f helm/otel-observability/values-minikube.yaml | grep -A 20 "kind: DaemonSet"
  ```
  Expected: lint clean, rendered manifest contains a DaemonSet with the three volume mounts and the four allowed labels only.

- [ ] **Step 4: Fix the Grafana ConfigMap, Deployment, Service, and Ingress templates.**

  Required (per plan Steps 2 and 3 of Task 5):
  - Prometheus as default data source; Jaeger as tracing; Loki as logs.
  - Trace-to-logs link configured using `traceID` / `trace_id` fields.
  - Log-to-trace derived fields with a regex matcher for trace IDs.
  - Dashboard with request rate, 5xx rate, P95 latency, JVM memory/**thread** panels, custom demo metrics, Collector health, Loki logs.
  - Service variable defaulting to `otel-springboot-demo` AND actually used by panel queries.
  - 1Gi PVC for Grafana state, parameterised via `grafana.persistence.size` in `values.yaml`.
  - NodePort / optional Ingress exposure.

  **Additional fix from audit:**
  - Add `grafana.persistence.size` to `values.yaml` if missing (default `1Gi`).
  - Make sure the Loki panel uses `$service` instead of hardcoded `otel-springboot-demo`.
  - Add the JVM thread panel (`sum(jvm_threads_live_threads)` by `area` or similar).

- [ ] **Step 5: Fix the dashboard JSON.**

  `helm/otel-observability/dashboards/otel-demo-dashboard.json` is missing two items per the audit:
  - **JVM threads panel** (plan requires "JVM memory/thread panels"). Add a panel with query `sum(jvm_threads_live_threads) by (area)` or equivalent.
  - **Use `$service` variable** in panel queries. Replace hardcoded `otel-springboot-demo` in the Loki panel with `$service`. Other panels may keep hardcoded queries.

  Validate the JSON:
  ```bash
  python3 -c "import json; json.load(open('helm/otel-observability/dashboards/otel-demo-dashboard.json'))" && echo "valid JSON"
  ```

- [ ] **Step 6: Review and finalize `tests/helm/test_grafana.sh`.**

  The script exists but may need fixes:
  - Replace hardcoded port numbers (`9090`, `16686`, `3100`) with values pulled from `values-minikube.yaml` (use `yq` or `helm template | grep -oP 'http://\K[^:]+'`).
  - Add an assertion that only the four low-cardinality labels (`namespace`, `pod`, `container`, `app`) appear in the Promtail relabel config.

  Run:
  ```bash
  bash tests/helm/test_grafana.sh
  helm lint helm/otel-observability
  ```
  Expected: both pass; test exits 0.

- [ ] **Step 7: Commit Task 5 on `feature/minikube-otel-cluster`.**

  Note: this plan (`docs/superpowers/plans/2026-09-04-continue-execution.md`) and the audit report (`docs/superpowers/plans/2026-09-04-audit-report.md`) are **not** part of the implementation — they belong to a separate docs commit (see below).

  ```bash
  git add helm/otel-observability/templates/promtail-daemonset.yaml \
          helm/otel-observability/templates/grafana-configmaps.yaml \
          helm/otel-observability/templates/grafana-deployment.yaml \
          helm/otel-observability/templates/grafana-service.yaml \
          helm/otel-observability/templates/ingress.yaml \
          helm/otel-observability/dashboards/otel-demo-dashboard.json \
          helm/otel-observability/values.yaml \
          tests/helm/test_grafana.sh
  git commit -m "feat: provision grafana logs and traces"
  ```
  Expected: working tree clean for these files; commit hash recorded.

### Task 6: Add Minikube lifecycle and end-to-end verification (FINISH)

**Status:** Script files created on disk, untracked, not committed. Drafts only.

**Files (review before commit):**
- Draft, review, finalize: `scripts/minikube-up.sh`
- Draft, review, finalize: `scripts/minikube-down.sh`
- Draft, review, finalize: `scripts/verify-observability.sh`
- Create or update: `helm/otel-observability/README.md`
- Create: `tests/integration/README.md`
- Update: `README.md` with deployment + troubleshooting sections

**Interfaces:**
- `minikube-up.sh` builds `otel-springboot-demo:local`, installs/upgrades the Chart, and prints service URLs.
- `minikube-down.sh` uninstalls the release and optionally deletes PVCs with explicit `--delete-data`.
- `verify-observability.sh` exits non-zero on any failed readiness, HTTP, Prometheus, Jaeger, Loki, or Grafana check.

- [ ] **Step 1: Verify rendered Deployment names match what the scripts reference.**

  Run:
  ```bash
  helm template otel-observability helm/otel-observability -f helm/otel-observability/values-minikube.yaml | grep -E "^kind: (Deployment|StatefulSet|DaemonSet)"
  ```
  Expected output includes `kind: Deployment` entries for `demo`, `otel-collector`, `grafana`; `kind: StatefulSet` for `prometheus`, `jaeger`, `loki`; `kind: DaemonSet` for `promtail` (when enabled).

  Update `minikube-up.sh` line 21 (the `kubectl rollout status` for the demo Deployment) to use the **actual** rendered name. If Helm generated `otel-observability-otel-observability-app` due to `fullnameOverride` not being set, fix that by adding `app.fullnameOverride: demo` in `values-minikube.yaml` so the Deployment is consistently named `demo`.

- [ ] **Step 2: Audit each script against the spec.**

  Required (per plan Step 1 of Task 6):
  - `--help` prints usage for each script.
  - Missing-command diagnostics are explicit and exit non-zero.
  - `minikube-down.sh` defaults to safe teardown; deleting PVCs requires `--delete-data`.

  Cross-reference each script with the audit report's Script section. Make a focused fix list.

- [ ] **Step 3: Finalize `scripts/minikube-up.sh`.**

  Required sequence:
  - `minikube start --cpus=6 --memory=8192`
  - `eval "$(minikube docker-env)"`
  - `mvn clean package`
  - `docker build -t otel-springboot-demo:local .`
  - `helm lint helm/otel-observability`
  - `helm upgrade --install --create-namespace -n observability ...`
  - Readiness checks for **every** workload kind (Deployment + StatefulSet + DaemonSet). Use:
    - `kubectl rollout status deployment/<name> -n observability --timeout=180s` for `demo`, `otel-collector`, `grafana`.
    - `kubectl wait --for=jsonpath='.status.readyReplicas'=1 statefulset/<name> -n observability --timeout=180s` for `prometheus`, `jaeger`, `loki`.
    - `kubectl rollout status daemonset/promtail -n observability --timeout=180s` for `promtail`.
  - `minikube service ... --url` for `demo`, `grafana`, `prometheus`, `jaeger`, `loki`. Print each URL on its own line.

  Add a `trap` so a failed step leaves the cluster running for debugging instead of silent exit.

- [ ] **Step 4: Finalize `scripts/minikube-down.sh`.**

  Required behavior:
  - Uninstall only the named release by default.
  - Delete PVCs only when `--delete-data` is supplied.
  - Never stop/delete unrelated Minikube profiles.

- [ ] **Step 5: Finalize `scripts/verify-observability.sh`.**

  Required checks:
  - Wait for all Pods to be Ready across all workload kinds:
    ```bash
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/part-of=otel-observability -n observability --timeout=180s
    ```
  - Call `/api/hello`, `/api/orders/1001`, `/api/load?count=50`, `/api/error`.
  - Query Prometheus via `minikube service prometheus --url` (NOT in-cluster DNS):
    ```bash
    prometheus_url="$(minikube service prometheus -n observability --url | head -n 1)"
    for query in 'up' 'demo_orders_total' 'demo_errors_total' 'http_server_requests_seconds_count'; do
      curl --fail --silent --get "${prometheus_url}/api/v1/query" --data-urlencode "query=$query" | grep -q '"success"'
    done
    ```
  - Query Jaeger for `otel-springboot-demo`:
    ```bash
    jaeger_url="$(minikube service jaeger -n observability --url | head -n 1)"
    curl --fail --silent "${jaeger_url}/api/services" | grep -q 'otel-springboot-demo'
    ```
  - Query Loki for the demo logs:
    ```bash
    loki_url="$(minikube service loki -n observability --url | head -n 1)"
    curl --fail --silent -G "${loki_url}/loki/api/v1/query_range" \
      --data-urlencode 'query={namespace="observability",app="otel-springboot-demo"}' \
      --data-urlencode 'limit=10' | grep -q '"status":"success"'
    ```
  - Assert Grafana data sources are provisioned (check `/api/datasources/name/{Prometheus,Jaeger,Loki}`).
  - Exit non-zero on any failure.

- [ ] **Step 6: Smoke-test the scripts locally without committing yet.**

  Run:
  ```bash
  bash scripts/minikube-up.sh --help
  bash scripts/minikube-down.sh --help
  bash scripts/verify-observability.sh --help
  bash tests/scripts/test_minikube_scripts.sh
  ```
  Expected: each script exits 0 with usage text; `test_minikube_scripts.sh` exits 0.

- [ ] **Step 7: Write `helm/otel-observability/README.md`.**

  Required sections:
  - Prerequisites (minikube, kubectl, helm, mvn, docker).
  - Resource requirements (cpus=6, memory=8192).
  - Installation (`./scripts/minikube-up.sh`).
  - URL list (demo, grafana, prometheus, jaeger, loki).
  - PromQL examples.
  - LogQL examples.
  - PVC/retention behavior.
  - Compatibility notes.
  - Common `kubectl` diagnostics (e.g., `kubectl logs`, `kubectl describe`, `kubectl get events`).
  - Expected verification output.

- [ ] **Step 8: Add `tests/integration/README.md`.**

  Explain how to run `verify-observability.sh` against a live Minikube, what each check verifies, troubleshooting common failures (404 from Jaeger means no traces yet; Loki empty means Promtail not scraping).

- [ ] **Step 9: Update top-level `README.md`.**

  Add sections: prerequisites, install, URL list, PromQL/LogQL examples, PVC/retention behavior, common `kubectl` diagnostics, and expected verification output.

- [ ] **Step 10: Commit Task 6 on `feature/minikube-otel-cluster`.**

  Implementation commit (scripts + chart README + tests/integration):
  ```bash
  git add scripts/ \
          helm/otel-observability/README.md \
          tests/integration/ \
          tests/scripts/
  git commit -m "test: add minikube observability verification"
  ```

  Top-level README update (separate commit because it's a top-level user-facing doc):
  ```bash
  git add README.md
  git commit -m "docs: link to helm chart and integration tests"
  ```

  Docs commit for the planning artifacts (this plan + the audit report):
  ```bash
  git add docs/superpowers/plans/2026-09-04-continue-execution.md \
          docs/superpowers/plans/2026-09-04-audit-report.md
  git commit -m "docs: add continue-execution plan and audit report"
  ```

### Task 7: Final verification, persistence recovery, and branch handoff

**Status:** Not started.

**Files:** Modify only what verification failures reveal.

- [ ] **Step 1: Verify local prerequisites.**

  Run:
  ```bash
  for cmd in minikube kubectl helm mvn docker; do command -v "$cmd" >/dev/null || { echo "missing: $cmd"; exit 1; }; done
  minikube status | grep -q 'Running' || { echo "minikube not running; start it manually or skip to script invocation"; }
  df -h / | awk 'NR==2 { if ($5+0 > 80) { print "disk >80% full; cleanup before continuing"; exit 1; } }'
  ```
  Expected: all six commands present, minikube running, disk not too full. If minikube is not running, `scripts/minikube-up.sh` will start it as part of its flow — but if minikube is missing entirely or the user has not approved a real cluster bring-up, **abort here** and ask the user for explicit permission before proceeding.

- [ ] **Step 2: Run the complete test suite end to end on a fresh Minikube.**

  ```bash
  cd .worktrees/minikube-otel-cluster
  mvn test
  helm lint helm/otel-observability
  bash tests/helm/test_render.sh
  bash tests/helm/test_collector_config.sh
  bash tests/helm/test_storage.sh
  bash tests/helm/test_grafana.sh
  bash scripts/minikube-up.sh
  bash scripts/verify-observability.sh
  ```
  Expected: every command exits 0. Save command-output summaries (not cluster state) for the handoff note.

- [ ] **Step 3: Test persistence recovery.**

  Restart every workload Pod and rerun the signal queries. **Do not hardcode deployment names** — query them first:
  ```bash
  kubectl get deploy,sts,ds -n observability -o jsonpath='{range .items[*]}{.kind}/{.metadata.name}{"\n"}{end}'
  ```
  Then use the **actual names** for `kubectl rollout restart` / `kubectl delete`:
  ```bash
  kubectl rollout restart deployment/demo deployment/otel-collector deployment/grafana -n observability
  kubectl delete pod -l app.kubernetes.io/name=prometheus -n observability
  kubectl delete pod -l app.kubernetes.io/name=jaeger -n observability
  kubectl delete pod -l app.kubernetes.io/name=loki -n observability
  ```
  Wait for Ready, then rerun `scripts/verify-observability.sh`. Expected: metrics, traces, and logs remain queryable from PVC-backed stores.

- [ ] **Step 4: Inspect the working tree and commits on the feature branch.**

  ```bash
  git status --short
  git log --oneline --decorate -10
  ```
  Expected: only intentional user changes remain uncommitted; one focused commit per Task 5/6/7.

- [ ] **Step 5: Hand off to `superpowers:finishing-a-development-branch`.**

  Present test evidence and **integration options** to the user. Do NOT push, merge, or open a PR. Let the user choose between:
  - merge to `main`
  - open a PR
  - keep the branch as-is for further iteration
  - discard the work

- [ ] **Step 6: After user decision, execute the chosen integration step.**

  Examples (do not run until user decides):
  ```bash
  # Option: merge to main
  cd ~/IdeaProjects/agentspace/otlp
  git checkout main
  git merge --no-ff feature/minikube-otel-cluster -m "Merge minikube observability chart"
  git worktree remove .worktrees/minikube-otel-cluster
  git branch -d feature/minikube-otel-cluster

  # Option: open PR
  git push origin feature/minikube-otel-cluster
  # then use gh pr create
  ```

---

## Status Summary

| Task | Subject | Branch State | Working Tree | Plan steps |
|---|---|---|---|---|
| 1 | Scaffolding | ✅ committed `f0b523e` | clean | done |
| 2 | Demo containerization | ✅ committed `f8ecc04` | clean | done |
| 3 | Collector pipelines | ✅ committed `c1b843f` | clean | done |
| 4 | Prometheus/Jaeger/Loki storage | ✅ committed `af56f94` | clean | done |
| 5 | Promtail + Grafana provisioning | 🟡 partially created, untracked | dirty | Steps 1–7 above |
| 6 | Minikube lifecycle scripts | 🟡 partially created, untracked | dirty | Steps 1–10 above |
| 7 | Final verification + handoff | 🔴 not started | clean | Steps 1–6 above |

**Working tree** is `.worktrees/minikube-otel-cluster` on `feature/minikube-otel-cluster`. Tasks 5–7 all execute from there.

## Audit Reference

The companion audit report at `docs/superpowers/plans/2026-09-04-audit-report.md` enumerates blockers per file. Treat it as a checklist while executing Tasks 5 and 6 — every blocker listed there should be addressed (or explicitly deferred with a written reason) before the corresponding Step's commit.

## Files Currently Untracked (review queue)

```
helm/otel-observability/dashboards/otel-demo-dashboard.json
helm/otel-observability/templates/grafana-configmaps.yaml
helm/otel-observability/templates/grafana-deployment.yaml
helm/otel-observability/templates/grafana-service.yaml
helm/otel-observability/templates/ingress.yaml
helm/otel-observability/templates/promtail-daemonset.yaml
helm/otel-observability/README.md
scripts/minikube-down.sh
scripts/minikube-up.sh
scripts/verify-observability.sh
tests/helm/test_grafana.sh
tests/integration/
tests/scripts/
```

These are drafts from a prior session; Tasks 5–6 Step 1 begins by verifying values keys; Step 2 reads the audit report to drive fixes; no code is committed before all blockers in the audit are addressed.

## Rollback

If a Task 5 or Task 6 commit breaks the chart or the verification script, revert with:

```bash
git reset --hard HEAD~1  # undo the most recent commit, keep changes in working tree
# or
git revert <commit-sha>   # safe revert that keeps history
```

The original plan (Tasks 1–4) is already on `main` and `feature/minikube-otel-cluster`; if this continuation goes wrong, the worktree branch can be discarded without touching `main`.

---

## Changelog

- **v2 (2026-09-04):** Rewritten after a self-audit identified 7 issues:
  1. Added Scope Check section to header.
  2. Documented dashboard.json path move (accepted: chart-relative).
  3. Added explicit Step 1 for values.yaml key verification.
  4. Added explicit Step 5 for dashboard.json fixes (JVM thread panel + `$service`).
  5. Rewrote "Write test_grafana.sh" to "Review and finalize" (file exists).
  6. Added Task 7 Step 1 prerequisites check (minikube/kubectl/helm/mvn/docker + disk space).
  7. Made Task 7 Step 3 query deployment names instead of hardcoding.
  8. Changed Task 7 Step 5/6 from auto-merge to present options for user choice.
  9. Added Rollback section.
  10. Split commits: implementation vs top-level README vs planning docs.

- v1 (2026-09-04): Initial draft.
