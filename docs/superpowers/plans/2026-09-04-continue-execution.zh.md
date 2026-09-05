# Minikube OpenTelemetry 本地集群 — 续执行计划 (v2)

> **致 agentic worker:** 必备子技能: 使用 superpowers:subagent-driven-development(推荐)或 superpowers:executing-plans 按 task 逐步实现本计划。步骤用 `- [ ]` 复选框追踪。
>
> **背景:** 本计划是原 `2026-08-02-minikube-opentelemetry-implementation.md` 的续篇。Tasks 1–4 **已提交**到 `feature/minikube-otel-cluster`。Tasks 5–6 **已开始但未提交**(文件已在磁盘)。Task 7 **未开始**。请先读原计划了解架构背景。
>
> **范围检查:** 本计划完成原 spec 已拆分的单个部署系统的剩余 3 个子任务(7 个中的 5/6/7)。无需进一步拆分子 spec。本续篇不引入新的功能需求。

**目标:** 完成 Minikube OpenTelemetry 部署计划的 Tasks 5–7 — 完善未提交的 Grafana/Promtail/Minikube 生命周期工作、提交,然后通过 `superpowers:finishing-a-development-branch` 把 `feature/minikube-otel-cluster` 交给用户审核并选择集成方式。

**架构:** 同原计划 — 一个 Umbrella Chart,包含 demo、Collector、Prometheus、Grafana、Jaeger、Loki、Promtail。应用遥测用 OTLP,K8s stdout 日志给 Promtail,PVC 持久化本地存储,Grafana provisioning 做跨信号导航。

**技术栈:** Java 8, Spring Boot 2.7.18, Maven, OpenTelemetry Java Agent, Docker, Kubernetes, Minikube, Helm, OpenTelemetry Collector Contrib, Prometheus, Grafana, Jaeger, Loki, Promtail。

## 全局约束

- 最终本地部署入口是 Helm on Minikube;Docker Compose 仅作参考。
- 保持 Java 8 和 Spring Boot 2.7.18 兼容性。
- 默认 namespace 是 `observability`。
- 默认存储用 Minikube `standard` StorageClass 和 PVC。
- metric 和 log 标签保持低基数;绝不索引订单 ID 或请求 ID。
- 在 values 里固定组件镜像和 Java Agent 版本,并校验渲染后的配置。
- 不引入 Kubernetes Operator、生产级 HA 或离线镜像仓库。
- **Tasks 5–7 的工作目录是已有 worktree** `.worktrees/minikube-otel-cluster`,在分支 `feature/minikube-otel-cluster` 上 — 不要新建 worktree。
- 当前磁盘上的未跟踪文件(Promtail DaemonSet、Grafana templates、scripts、dashboards、tests)都是**待审稿**,不是成品 — 提交前对照本计划要求逐个 diff。
- **假设已存在的 Helm values 键**(在 Tasks 1–4 的 `values.yaml` 里定义): `images.<component>.repository/tag`, `prometheus.service.port`, `jaeger.service.{port,uiPort}`, `loki.service.port`, `app.service.port`, `grafana.service.{type,port,nodePort,adminUser,adminPassword,replicas,resources}`, `grafana.persistence.enabled`, `promtail.{enabled,resources}`, `ingress.{enabled,className,hostSuffix}`。**渲染前先验证** — 打开 `helm/otel-observability/values.yaml` 确认。如有缺失,先补到 values.yaml 再继续。
- **Dashboard 位置决定:** 当前 draft 把 `otel-demo-dashboard.json` 放在 `helm/otel-observability/dashboards/`(原 plan 放 `grafana/dashboards/`)。**接受**这次移动 — 把 dashboard 放在 chart 内部让 chart 自包含。原 `grafana/dashboards/otel-demo-dashboard.json` 保留作参考,不再被渲染。

---

### Task 5: 添加 Promtail 和 Grafana provisioning (完成)

**状态:** 文件已在磁盘,未跟踪,未提交,只是 draft。

**Files (提交前审查):**
- Draft, 审查, 完成: `helm/otel-observability/templates/promtail-daemonset.yaml`
- Draft, 审查, 完成: `helm/otel-observability/templates/grafana-configmaps.yaml`
- Draft, 审查, 完成: `helm/otel-observability/templates/grafana-deployment.yaml`
- Draft, 审查, 完成: `helm/otel-observability/templates/grafana-service.yaml`
- Draft, 审查, 完成: `helm/otel-observability/templates/ingress.yaml`
- 已存在(chart 内,接受): `helm/otel-observability/dashboards/otel-demo-dashboard.json` — 按 audit 修复 (Step 5)
- 已存在 draft: `tests/helm/test_grafana.sh` — 审查并完成 (原 Step 5,现 Step 6)

**接口:**
- Promtail 发 node container 日志到 `http://loki:3100/loki/api/v1/push`。
- Grafana 消费 `prometheus:9090`, `jaeger:16686`, `loki:3100`。

- [ ] **Step 1: 验证 draft 模板用到的 Helm values 键是否存在。**

  打开 `helm/otel-observability/values.yaml`,确认 5 个 Grafana/Promtail 模板里引用的每个键都已定义。需要检查:`images.promtail.repository/tag`, `images.grafana.repository/tag`, `grafana.{replicas,adminUser,adminPassword,resources,persistence.enabled}`, `prometheus.service.port`, `jaeger.service.uiPort`, `loki.service.port`, `grafana.service.{type,port,nodePort}`, `promtail.{enabled,resources}`, `ingress.{enabled,className,hostSuffix}`。如有缺失,补到 `values.yaml` 并在 commit message 里说明。

- [ ] **Step 2: 对照原 plan spec 逐个审查 draft。**

  原 plan: `docs/superpowers/plans/2026-08-02-minikube-opentelemetry-implementation.md` 的 Task 5。
  Cross-reference 每个 draft 与 audit report (`docs/superpowers/plans/2026-09-04-audit-report.md`)。Audit Top 5 阻塞问题(Promtail containerd 路径、JVM thread panel、deployment 名检查等)列在那里。先列出修复清单,别动手。

- [ ] **Step 3: 修复 Promtail DaemonSet 满足 spec。**

  必需项(per plan Step 1 of Task 5):
  - 挂载 `/var/log/pods`、`/var/log/containers` 和 Docker/containerd 位置文件,适当 read-only。
  - 解析 K8s metadata。
  - 只发低基数标签(`namespace`, `pod`, `container`, `app`)给 Loki。
  - readiness probe 存在。
  - `promtail.enabled` gate 生效。
  - **Audit 额外修复:** 参数化 Docker/containerd 容器日志目录,让 chart 在 Minikube 默认 (containerd) 和 Docker 上都能跑。在 `values.yaml` 加 `promtail.containerLogsDir`(默认 `/var/lib/docker/containers`)。

  运行:
  ```bash
  helm lint helm/otel-observability
  helm template otel-observability helm/otel-observability -f helm/otel-observability/values-minikube.yaml | grep -A 20 "kind: DaemonSet"
  ```
  预期:lint 通过,渲染出的 manifest 含 DaemonSet + 3 个 volumeMount + 只 4 个允许的标签。

- [ ] **Step 4: 修复 Grafana ConfigMap、Deployment、Service 和 Ingress 模板。**

  必需项(per plan Steps 2 and 3 of Task 5):
  - Prometheus 作为 default 数据源;Jaeger 作为 tracing;Loki 作为 logs。
  - 用 `traceID` / `trace_id` 字段配 trace-to-logs 链接。
  - 用正则匹配 trace ID 的 log-to-trace derived fields。
  - Dashboard 含 request rate、5xx rate、P95 latency、JVM memory/**thread** 面板、custom demo metrics、Collector health、Loki logs。
  - Service 变量默认 `otel-springboot-demo` **且** 面板查询真正用到。
  - Grafana state 1Gi PVC,通过 `grafana.persistence.size` 参数化。
  - NodePort / 可选 Ingress 暴露。

  **Audit 额外修复:**
  - 如 `grafana.persistence.size` 在 `values.yaml` 缺失,加上(默认 `1Gi`)。
  - 确保 Loki 面板用 `$service` 而不是硬编码 `otel-springboot-demo`。
  - 加 JVM thread panel (`sum(jvm_threads_live_threads)` by `area` 或类似)。

- [ ] **Step 5: 修复 dashboard JSON。**

  `helm/otel-observability/dashboards/otel-demo-dashboard.json` 按 audit 缺两项:
  - **JVM threads panel**(plan 要求 "JVM memory/thread panels")。加一个 panel 用 `sum(jvm_threads_live_threads) by (area)` 或等价查询。
  - **用 `$service` 变量**。把 Loki 面板里硬编码的 `otel-springboot-demo` 替换为 `$service`。其他面板可以保留硬编码查询。

  校验 JSON:
  ```bash
  python3 -c "import json; json.load(open('helm/otel-observability/dashboards/otel-demo-dashboard.json'))" && echo "valid JSON"
  ```

- [ ] **Step 6: 审查并完成 `tests/helm/test_grafana.sh`。**

  脚本已存在,可能需要修复:
  - 用 `values-minikube.yaml` 里的值替换硬编码端口(`9090`, `16686`, `3100`)(用 `yq` 或 `helm template | grep -oP 'http://\K[^:]+'`)。
  - 加一条断言:Promtail relabel 配置里只出现 4 个低基数标签(`namespace`, `pod`, `container`, `app`)。

  运行:
  ```bash
  bash tests/helm/test_grafana.sh
  helm lint helm/otel-observability
  ```
  预期:两者都通过;test 退出码 0。

- [ ] **Step 7: 在 `feature/minikube-otel-cluster` 提交 Task 5。**

  注:本计划(`docs/superpowers/plans/2026-09-04-continue-execution.md`)和 audit report(`docs/superpowers/plans/2026-09-04-audit-report.md`)**不属于**实现 — 单独走一个 docs commit(见下)。

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
  预期:working tree 干净,得到 commit hash。

### Task 6: 添加 Minikube 生命周期和端到端验证 (完成)

**状态:** 脚本文件已在磁盘,未跟踪,未提交,只是 draft。

**Files (提交前审查):**
- Draft, 审查, 完成: `scripts/minikube-up.sh`
- Draft, 审查, 完成: `scripts/minikube-down.sh`
- Draft, 审查, 完成: `scripts/verify-observability.sh`
- 创建或更新: `helm/otel-observability/README.md`
- 创建: `tests/integration/README.md`
- 更新: `README.md` 加部署 + 排障章节

**接口:**
- `minikube-up.sh` 构建 `otel-springboot-demo:local`、安装/升级 Chart、打印 service URLs。
- `minikube-down.sh` 卸载 release,可选加 `--delete-data` 删 PVC。
- `verify-observability.sh` 任何 readiness、HTTP、Prometheus、Jaeger、Loki、Grafana 检查失败时非零退出。

- [ ] **Step 1: 验证渲染出的 Deployment 名是否匹配脚本里的引用。**

  运行:
  ```bash
  helm template otel-observability helm/otel-observability -f helm/otel-observability/values-minikube.yaml | grep -E "^kind: (Deployment|StatefulSet|DaemonSet)"
  ```
  预期输出含:`kind: Deployment` 条目为 `demo`, `otel-collector`, `grafana`;`kind: StatefulSet` 为 `prometheus`, `jaeger`, `loki`;`kind: DaemonSet` 为 `promtail`(当 enabled)。

  修 `minikube-up.sh` line 21(demo Deployment 的 `kubectl rollout status`)用**实际渲染的名**。如果 Helm 生成了 `otel-observability-otel-observability-app`(因为没设 `fullnameOverride`),就在 `values-minikube.yaml` 加 `app.fullnameOverride: demo` 让 Deployment 名稳定为 `demo`。

- [ ] **Step 2: 对照 spec 审查每个脚本。**

  必需项(per plan Step 1 of Task 6):
  - `--help` 打印 usage。
  - 缺命令时诊断信息明确并非零退出。
  - `minikube-down.sh` 默认安全卸载;删 PVC 必须显式 `--delete-data`。

  Cross-reference 每个脚本与 audit report 的 Script 章节。列修复清单。

- [ ] **Step 3: 完成 `scripts/minikube-up.sh`。**

  必需步骤序列:
  - `minikube start --cpus=6 --memory=8192`
  - `eval "$(minikube docker-env)"`
  - `mvn clean package`
  - `docker build -t otel-springboot-demo:local .`
  - `helm lint helm/otel-observability`
  - `helm upgrade --install --create-namespace -n observability ...`
  - 对**每种** workload 类型做 readiness 检查(Deployment + StatefulSet + DaemonSet)。用法:
    - `kubectl rollout status deployment/<name> -n observability --timeout=180s` 用于 `demo`, `otel-collector`, `grafana`。
    - `kubectl wait --for=jsonpath='.status.readyReplicas'=1 statefulset/<name> -n observability --timeout=180s` 用于 `prometheus`, `jaeger`, `loki`。
    - `kubectl rollout status daemonset/promtail -n observability --timeout=180s` 用于 `promtail`。
  - `minikube service ... --url` 打印 `demo`, `grafana`, `prometheus`, `jaeger`, `loki` 的 URL,每行一个。

  加一个 `trap`,失败时让 cluster 留着方便排障,而不是静默退出。

- [ ] **Step 4: 完成 `scripts/minikube-down.sh`。**

  必需行为:
  - 默认只卸载指定 release。
  - 只有在 `--delete-data` 显式给出时才删 PVC。
  - 永远不要停/删无关的 Minikube profile。

- [ ] **Step 5: 完成 `scripts/verify-observability.sh`。**

  必需检查:
  - 等待所有 Pod Ready(跨所有 workload 类型):
    ```bash
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/part-of=otel-observability -n observability --timeout=180s
    ```
  - 调 `/api/hello`, `/api/orders/1001`, `/api/load?count=50`, `/api/error`。
  - 通过 `minikube service prometheus --url` 查 Prometheus(**不要**用 in-cluster DNS):
    ```bash
    prometheus_url="$(minikube service prometheus -n observability --url | head -n 1)"
    for query in 'up' 'demo_orders_total' 'demo_errors_total' 'http_server_requests_seconds_count'; do
      curl --fail --silent --get "${prometheus_url}/api/v1/query" --data-urlencode "query=$query" | grep -q '"success"'
    done
    ```
  - 查 Jaeger 的 `otel-springboot-demo`:
    ```bash
    jaeger_url="$(minikube service jaeger -n observability --url | head -n 1)"
    curl --fail --silent "${jaeger_url}/api/services" | grep -q 'otel-springboot-demo'
    ```
  - 查 Loki 的 demo 日志:
    ```bash
    loki_url="$(minikube service loki -n observability --url | head -n 1)"
    curl --fail --silent -G "${loki_url}/loki/api/v1/query_range" \
      --data-urlencode 'query={namespace="observability",app="otel-springboot-demo"}' \
      --data-urlencode 'limit=10' | grep -q '"status":"success"'
    ```
  - 断言 Grafana 数据源已 provisioning(检查 `/api/datasources/name/{Prometheus,Jaeger,Loki}`)。
  - 任何失败时退出码非零。

- [ ] **Step 6: 本地 smoke-test 脚本,先不提交。**

  运行:
  ```bash
  bash scripts/minikube-up.sh --help
  bash scripts/minikube-down.sh --help
  bash scripts/verify-observability.sh --help
  bash tests/scripts/test_minikube_scripts.sh
  ```
  预期:每个脚本退出码 0 打印 usage;`test_minikube_scripts.sh` 退出码 0。

- [ ] **Step 7: 写 `helm/otel-observability/README.md`。**

  必需章节:
  - 前置条件 (minikube, kubectl, helm, mvn, docker)。
  - 资源需求 (cpus=6, memory=8192)。
  - 安装 (`./scripts/minikube-up.sh`)。
  - URL 清单 (demo, grafana, prometheus, jaeger, loki)。
  - PromQL 示例。
  - LogQL 示例。
  - PVC/retention 行为。
  - 兼容性说明。
  - 常用 `kubectl` 诊断命令(如 `kubectl logs`、`kubectl describe`、`kubectl get events`)。
  - 预期验证输出。

- [ ] **Step 8: 加 `tests/integration/README.md`。**

  说明如何在 live Minikube 上跑 `verify-observability.sh`,每项检查验证什么,常见失败排障(Jaeger 返 404 表示还没 trace;Loki 空表示 Promtail 没在抓取)。

- [ ] **Step 9: 更新顶层 `README.md`。**

  加章节:前置条件、安装、URL 清单、PromQL/LogQL 示例、PVC/retention 行为、常用 `kubectl` 诊断命令、预期验证输出。

- [ ] **Step 10: 在 `feature/minikube-otel-cluster` 提交 Task 6。**

  实现 commit (scripts + chart README + tests/integration):
  ```bash
  git add scripts/ \
          helm/otel-observability/README.md \
          tests/integration/ \
          tests/scripts/
  git commit -m "test: add minikube observability verification"
  ```

  顶层 README 更新(独立 commit,因为是顶层面向用户的文档):
  ```bash
  git add README.md
  git commit -m "docs: link to helm chart and integration tests"
  ```

  计划文档 commit(本计划 + audit report):
  ```bash
  git add docs/superpowers/plans/2026-09-04-continue-execution.md \
          docs/superpowers/plans/2026-09-04-audit-report.md
  git commit -m "docs: add continue-execution plan and audit report"
  ```

### Task 7: 最终验证、持久化恢复和分支交接

**状态:** 未开始。

**Files:** 只在验证失败时修改必要文件。

- [ ] **Step 1: 验证本地前置条件。**

  运行:
  ```bash
  for cmd in minikube kubectl helm mvn docker; do command -v "$cmd" >/dev/null || { echo "missing: $cmd"; exit 1; }; done
  minikube status | grep -q 'Running' || { echo "minikube not running; start it manually or skip to script invocation"; }
  df -h / | awk 'NR==2 { if ($5+0 > 80) { print "disk >80% full; cleanup before continuing"; exit 1; } }'
  ```
  预期:六个命令都在,minikube 在跑,磁盘不紧张。如果 minikube 没跑,`scripts/minikube-up.sh` 会在自己流程里启动它 — 但如果 minikube 完全没装或用户没批准起真集群,**在这里中止**,先要用户明确批准。

- [ ] **Step 2: 在全新 Minikube 上端到端跑完整测试套件。**

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
  预期:每个命令退出码 0。把命令输出摘要保存(不要保存 cluster state)给交接 note。

- [ ] **Step 3: 测持久化恢复。**

  重启每个 workload Pod,再跑信号查询。**不要硬编码 deployment 名** — 先查:
  ```bash
  kubectl get deploy,sts,ds -n observability -o jsonpath='{range .items[*]}{.kind}/{.metadata.name}{"\n"}{end}'
  ```
  然后用**实际名**做 `kubectl rollout restart` / `kubectl delete`:
  ```bash
  kubectl rollout restart deployment/demo deployment/otel-collector deployment/grafana -n observability
  kubectl delete pod -l app.kubernetes.io/name=prometheus -n observability
  kubectl delete pod -l app.kubernetes.io/name=jaeger -n observability
  kubectl delete pod -l app.kubernetes.io/name=loki -n observability
  ```
  等 Ready,再跑 `scripts/verify-observability.sh`。预期:PVC 后端存储里 metric、trace、log 仍可查。

- [ ] **Step 4: 检查 working tree 和 feature branch 上的 commit。**

  ```bash
  git status --short
  git log --oneline --decorate -10
  ```
  预期:只有刻意保留的未提交文件;每个 Task 5/6/7 一个聚焦 commit。

- [ ] **Step 5: 交接给 `superpowers:finishing-a-development-branch`。**

  把测试证据和**集成选项**呈现给用户。**不要**自己 push、merge 或开 PR。让用户在以下选项中选:
  - merge 到 `main`
  - 开 PR
  - 保留分支继续迭代
  - 丢弃

- [ ] **Step 6: 用户决定后,执行选定的集成步骤。**

  示例(用户没决定前不要跑):
  ```bash
  # 选项: merge 到 main
  cd ~/IdeaProjects/agentspace/otlp
  git checkout main
  git merge --no-ff feature/minikube-otel-cluster -m "Merge minikube observability chart"
  git worktree remove .worktrees/minikube-otel-cluster
  git branch -d feature/minikube-otel-cluster

  # 选项: 开 PR
  git push origin feature/minikube-otel-cluster
  # 然后用 gh pr create
  ```

---

## 状态摘要

| Task | 主题 | 分支状态 | Working Tree | Plan 步骤 |
|---|---|---|---|---|
| 1 | Scaffolding | ✅ committed `f0b523e` | clean | done |
| 2 | Demo containerization | ✅ committed `f8ecc04` | clean | done |
| 3 | Collector pipelines | ✅ committed `c1b843f` | clean | done |
| 4 | Prometheus/Jaeger/Loki storage | ✅ committed `af56f94` | clean | done |
| 5 | Promtail + Grafana provisioning | 🟡 已部分创建,未跟踪 | dirty | 上面 Steps 1–7 |
| 6 | Minikube 生命周期脚本 | 🟡 已部分创建,未跟踪 | dirty | 上面 Steps 1–10 |
| 7 | 最终验证 + 交接 | 🔴 未开始 | clean | 上面 Steps 1–6 |

**Working tree** 是 `.worktrees/minikube-otel-cluster` 在 `feature/minikube-otel-cluster` 分支上。Tasks 5–7 都在这里执行。

## 审计报告引用

配套 audit report (`docs/superpowers/plans/2026-09-04-audit-report.md`) 按文件列出了阻塞问题。执行 Tasks 5、6 时把它当 checklist 用 — audit 列出的每个阻塞问题,要么修了,要么显式延期(写明原因),再做对应 Step 的 commit。

## 当前未跟踪的文件(待审稿)

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

这些都是上次 session 留下的 draft;Tasks 5–6 Step 1 先验 values keys,Step 2 读 audit report 找修复清单,在 audit 列出的阻塞问题没解决前不要 commit 任何代码。

## 回滚

如果 Task 5 或 Task 6 commit 把 chart 弄坏了,这样回滚:

```bash
git reset --hard HEAD~1  # 撤销最近一次 commit,改动留在 working tree
# 或
git revert <commit-sha>   # 安全回滚,保留历史
```

原 plan(Tasks 1–4)已经在 `main` 和 `feature/minikube-otel-cluster`;这次续做如果出问题,worktree 分支可以直接丢,**不影响 `main`**。

---

## Changelog

- **v2 (2026-09-04):** 自审发现 7 个问题后重写:
  1. Header 加 Scope Check 段。
  2. 文档说明 dashboard.json 路径移动(接受:chart 内部)。
  3. 加显式 Step 1 验证 values.yaml keys。
  4. 加显式 Step 5 修复 dashboard.json (JVM thread panel + `$service`)。
  5. 把 "Write test_grafana.sh" 改为 "Review and finalize"(文件已存在)。
  6. Task 7 加 Step 1 前置条件检查(minikube/kubectl/helm/mvn/docker + 磁盘空间)。
  7. Task 7 Step 3 改为先查 deployment 名而不是硬编码。
  8. Task 7 Step 5/6 从自动 merge 改为呈现选项让用户选。
  9. 加 Rollback 段。
  10. 拆分 commits:实现 vs 顶层 README vs 计划文档。

- v1 (2026-09-04): 初版。
