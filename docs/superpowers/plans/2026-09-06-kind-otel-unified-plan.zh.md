# Kind OpenTelemetry 本地可观测集群统一实施计划

> **供智能代理执行：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`，逐项执行本计划。复选框 `[x]` 表示已有代码、提交或验证证据；`[ ]` 表示仍需执行和记录证据。

**目标：** 在 Kind 上维护一个基于 Helm 的本地 Kubernetes 可观测环境，使 Java 8 / Spring Boot 2.7 Demo 的指标、链路和日志可以由 OpenTelemetry Collector 接收，并由 Prometheus、Jaeger、Loki 和 Grafana 查询与展示。

**架构：** 一个 Umbrella Helm Chart 部署 Demo、OpenTelemetry Collector、Prometheus、Grafana、Jaeger、Loki 和 Promtail。应用通过 OTLP 发送遥测，Promtail 从 Kubernetes 节点日志目录采集 stdout 日志，后端使用 PVC 保存本地数据，Grafana 统一提供跨信号导航。

**技术栈：** Java 8、Spring Boot 2.7.18、Maven、OpenTelemetry Java Agent、Docker、Kubernetes、Kind、Helm、OpenTelemetry Collector Contrib、Prometheus、Grafana、Jaeger、Loki、Promtail。

## 全局约束

- 最终本地部署入口是在 Kind 上执行 Helm；Docker Compose 仅作为参考。
- 保持 Java 8 和 Spring Boot 2.7.18 兼容。
- 默认命名空间是 `observability`，默认 Helm release 是 `otel-observability`。
- Kind 使用集群默认 StorageClass 和 PVC，并通过 `values-kind.yaml` 适配 ClusterIP 等环境差异。
- 指标和日志标签必须保持低基数，不得把 order ID 或 request ID 建成指标或 Loki 标签。
- 所有组件镜像和 OpenTelemetry Java Agent 版本必须固定，并验证最终渲染结果。
- 不引入 Kubernetes Operator、生产级 HA 或离线镜像仓库。
- 历史 Kind 验证可以证明已完成部分，但不能替代 Promtail/Loki 日志链路和 PVC 恢复验证。

---

## 1. 权威状态与证据规则

### 1.1 当前仓库状态

- [x] Tasks 1–4 已分别由 `f0b523e`、`f8ecc04`、`c1b843f`、`af56f94` 实现。
- [x] Task 5 由 `d811fea` 实现。
- [x] Task 6 由 `f991ada` 和 `ae2c5a1` 实现并补充文档。
- [x] Kind 现场验证发现的 Chart 修复由 `4e57fe9` 提交。
- [x] 功能分支通过 merge commit `a4bee10` 合入 `main`。
- [x] 2026-09-06 重新运行单元、Helm 和脚本测试，退出码为 0。
- [x] 在 Kind 集群解决 inotify 限制并完成 Promtail/Loki 日志链路验收。
- [x] 完成 PVC 后端重启恢复验收。
- [x] 把最终动态验收摘要写回本计划并将总状态改为完成。

### 1.2 证据分级

- `[x] 实现完成`：源码和对应提交存在，并且静态/单元测试通过。
- `[x] Kind 已验证`：提交 `4e57fe9` 的现场记录证明指定功能曾在 `kind-migration` 集群运行。
- `[ ] 动态验收`：必须在当前可访问的集群重新运行命令并保存结果摘要；不能仅凭提交说明勾选。
- Helm lint/template 只能证明渲染有效，不能证明工作负载就绪、网络可达或数据持久化。

---

### Task 1：Chart 与测试脚手架（已完成）

**文件：**
- `.gitignore`
- `helm/otel-observability/Chart.yaml`
- `helm/otel-observability/values.yaml`
- `helm/otel-observability/values-minikube.yaml`
- `helm/otel-observability/templates/_helpers.tpl`
- `tests/helm/test_render.sh`

**产出接口：** Helm release `otel-observability`、命名空间 `observability`，以及后续模板共同使用的 values contract。

- [x] 创建隔离 feature worktree 和 `feature/minikube-otel-cluster` 分支。
- [x] 定义 Chart 元数据、镜像、服务、存储、资源、探针和组件开关。
- [x] 添加模板 helper 和渲染冒烟测试。
- [x] 验证七个组件、OTLP `4317/4318` 端口及 PVC 声明。
- [x] 提交：`f0b523e build: scaffold minikube observability helm chart`。

复验命令：

```bash
helm lint helm/otel-observability
bash tests/helm/test_render.sh
```

预期：Chart lint 0 失败，渲染测试退出码 0。

---

### Task 2：Java Demo 容器化（已完成）

**文件：**
- `Dockerfile`
- `src/main/resources/application.yml`
- `src/main/java/com/example/otel/DemoController.java`
- `src/test/java/com/example/otel/DemoControllerTest.java`
- `helm/otel-observability/templates/app-deployment.yaml`
- `helm/otel-observability/templates/app-service.yaml`

**产出接口：** Service `demo:8080`，健康检查端点和 OTLP 环境变量；提供 `/api/hello`、`/api/orders/{id}`、`/api/load`、`/api/error`。

- [x] 为四类 HTTP 行为添加 MVC 测试。
- [x] 保持 stdout 日志和低基数自定义指标属性。
- [x] 固定 Java 8 容器与 Java Agent 下载版本。
- [x] 配置 `OTEL_SERVICE_NAME`、资源属性、OTLP gRPC endpoint 和探针。
- [x] 提交：`f8ecc04 feat: containerize spring boot otel demo for minikube`。

复验命令：

```bash
mvn test
helm template otel-observability helm/otel-observability \
  -f helm/otel-observability/values-minikube.yaml
```

预期：5 个 Java 测试通过，模板渲染退出码 0。

---

### Task 3：Collector 三信号管道（已完成）

**文件：**
- `helm/otel-observability/templates/collector-configmap.yaml`
- `helm/otel-observability/templates/collector-deployment.yaml`
- `helm/otel-observability/templates/collector-service.yaml`
- `tests/helm/test_collector_config.sh`

**产出接口：** OTLP gRPC/HTTP 接收端口 `4317/4318`、Prometheus exporter `8889`，以及 traces、metrics、logs 三条 pipeline。

- [x] 配置 OTLP receivers、`memory_limiter`、`resource`、`batch`。
- [x] 配置 Prometheus、Jaeger 和 Loki exporters 及 retry/queue。
- [x] 配置非 root 安全上下文、资源、探针和配置 checksum。
- [x] 测试拒绝 order ID/request ID 高基数标签。
- [x] 提交：`c1b843f feat: add otel collector pipelines`。

复验命令：

```bash
bash tests/helm/test_collector_config.sh
helm lint helm/otel-observability
```

预期：配置测试和 lint 均退出 0。

---

### Task 4：Prometheus、Jaeger 与 Loki 持久化后端（实现完成）

**文件：**
- `helm/otel-observability/templates/prometheus-*`
- `helm/otel-observability/templates/jaeger-*`
- `helm/otel-observability/templates/loki-*`
- `helm/otel-observability/templates/pvc.yaml`
- `tests/helm/test_storage.sh`

**产出接口：** Services `prometheus:9090`、`jaeger:16686/4317`、`loki:3100`，以及 PVC 支持的 StatefulSet。

- [x] Prometheus 抓取 Collector 和 Demo，并包含请求率、5xx、P95、订单率及 Collector 规则/告警。
- [x] Prometheus 使用 PVC 和 7 天 retention。
- [x] Jaeger 使用本地 Badger PVC，提供 UI 和 OTLP receiver。
- [x] Loki 使用 filesystem PVC、本地 schema 和 retention 配置。
- [x] 增加存储、Service 和端口渲染测试。
- [x] 提交：`af56f94 feat: add persistent metrics trace and log backends`。
- [x] Task 8 已动态证明 Pod 重启后 metrics、traces 和 logs 仍可查询。

复验命令：

```bash
bash tests/helm/test_storage.sh
helm template otel-observability helm/otel-observability \
  -f helm/otel-observability/values-minikube.yaml
```

---

### Task 5：Promtail 与 Grafana（实现完成，日志动态验收待完成）

**文件：**
- `helm/otel-observability/templates/promtail-daemonset.yaml`
- `helm/otel-observability/templates/grafana-configmaps.yaml`
- `helm/otel-observability/templates/grafana-deployment.yaml`
- `helm/otel-observability/templates/grafana-service.yaml`
- `helm/otel-observability/templates/ingress.yaml`
- `helm/otel-observability/dashboards/otel-demo-dashboard.json`
- `helm/otel-observability/values.yaml`
- `tests/helm/test_grafana.sh`

**产出接口：** Promtail 将节点容器日志发送到 `http://loki:3100/loki/api/v1/push`；Grafana 使用 Prometheus、Jaeger 和 Loki 数据源。

- [x] Promtail 挂载 `/var/log/pods`、`/var/log/containers` 和参数化的 `promtail.containerLogsDir`。
- [x] Promtail 只输出 `namespace`、`pod`、`container`、`app` 四类低基数标签。
- [x] Promtail 具有 readiness、RBAC 和 `promtail.enabled` gate。
- [x] Grafana 配置 Prometheus 默认数据源、Jaeger、Loki、trace-to-logs 和 derived fields。
- [x] Dashboard 包含 request rate、5xx、P95、JVM memory/thread、自定义指标、Collector health 和 Loki logs。
- [x] Dashboard Loki 查询使用 `$service` 变量。
- [x] Grafana PVC 大小通过 `grafana.persistence.size` 参数化，默认 `1Gi`。
- [x] Grafana 支持 NodePort 和可选 Ingress。
- [x] `tests/helm/test_grafana.sh` 验证数据源、Dashboard、端口和低基数标签。
- [x] 提交：`d811fea feat: provision grafana logs and traces`。
- [x] Kind 现场发现并修复 Promtail 重复 mountPath 和 securityContext 层级问题：`4e57fe9`。
- [x] Task 8 已在 Kind 完成 Promtail Ready 和 Loki 日志查询。

复验命令：

```bash
bash tests/helm/test_grafana.sh
helm lint helm/otel-observability
```

---

### Task 6：本地集群生命周期、验证脚本和文档（兼容工具已完成）

**文件：**
- `scripts/minikube-up.sh`
- `scripts/minikube-down.sh`
- `scripts/verify-observability.sh`
- `tests/scripts/test_minikube_scripts.sh`
- `helm/otel-observability/README.md`
- `tests/integration/README.md`
- `README.md`

**产出接口：** 已有 Minikube 一键启动/安全卸载兼容工具和通用端到端信号检查；Kind 主部署使用 Task 7/8 中的 Helm 与 `kubectl port-forward`。

- [x] 三个脚本均支持 `--help`，并拒绝未知参数。
- [x] `minikube-up.sh` 启动集群、构建应用、安装 Chart、等待所有 workload 并打印服务 URL。
- [x] `minikube-down.sh` 默认只卸载 release，仅在 `--delete-data` 时删除 PVC，不删除 Minikube profile。
- [x] `verify-observability.sh` 检查 Pods、Demo endpoints、Prometheus、Jaeger、Loki 和 Grafana。
- [x] Chart README 包含前置条件、资源、安装、URL、PromQL、LogQL、PVC、兼容性和排错。
- [x] integration README 说明检查内容和常见故障。
- [x] 提交：`f991ada test: add minikube observability verification`。
- [x] 顶层文档提交：`ae2c5a1 docs: link to helm chart and integration tests`。
- [x] Minikube 专属脚本作为兼容工具保留，不再作为本 Kind 计划的最终验收条件。

静态复验命令：

```bash
bash scripts/minikube-up.sh --help
bash scripts/minikube-down.sh --help
bash scripts/verify-observability.sh --help
bash tests/scripts/test_minikube_scripts.sh
```

预期：每条命令退出 0，help 命令输出 usage。

---

### Task 7：Hermes Kind 端到端验证与现场修复（已完成到已记录边界）

**环境：** 历史 `kind-migration` 集群；使用 `values-minikube.yaml` 与 `values-kind.yaml`，后者使用 ClusterIP 并禁用 Promtail。

**现场修复文件：**
- `helm/otel-observability/templates/app-service.yaml`
- `helm/otel-observability/templates/grafana-service.yaml`
- `helm/otel-observability/templates/jaeger-service.yaml`
- `helm/otel-observability/templates/loki-service.yaml`
- `helm/otel-observability/templates/prometheus-service.yaml`
- `helm/otel-observability/templates/promtail-daemonset.yaml`
- `helm/otel-observability/values-kind.yaml`
- `helm/otel-observability/values.yaml`

- [x] 修复 ClusterIP Service 不允许设置 `nodePort` 的问题。
- [x] 补充缺失的 Loki Service。
- [x] 修复 containerd 默认目录 `/var/log/pods` 导致的 Promtail 重复 mountPath。
- [x] 分离 Promtail pod/container securityContext。
- [x] Demo 四个端点返回 `200/200/200/500`。
- [x] Prometheus `up` 显示 2/2 targets，三个应用指标存在。
- [x] Jaeger `/api/services` 包含 `otel-springboot-demo`，记录到 6 个 operations。
- [x] Grafana 3/3 数据源已 provision，Dashboard 已加载。
- [x] Loki workload 可运行。
- [x] 提交：`4e57fe9 fix(chart): cluster e2e fixes found during verification on kind`。
- [x] 历史限制已记录：当时 Promtail 报 `too many open files`；Task 8 确认根因为共享内核 inotify instance 限制并完成验证。
- [x] 历史限制已记录：当时 Loki 无应用日志；Task 8 已修复标签契约并验证日志可查。

Kind 重现命令：

```bash
helm upgrade --install otel-observability helm/otel-observability \
  -n observability --create-namespace \
  -f helm/otel-observability/values-minikube.yaml \
  -f helm/otel-observability/values-kind.yaml
kubectl get deploy,sts,ds,pods,pvc -n observability
```

注意：只有实际重新运行并取得成功输出后，才能把上面的历史结果升级为“当前验证”。

---

### Task 8：完成剩余动态验收（已完成）

**文件：**
- 仅在发现真实缺陷时修改对应 Chart、values、脚本或测试文件。
- 验收完成后修改本计划的 Task 8 状态和“最终验收记录”。

**接口：** 消费当前 Chart 和验证脚本；产出 logs 全链路、PVC 恢复和最终完成证据。

- [x] **Step 1：确认执行环境和工具。**

```bash
for cmd in kind kubectl helm mvn docker curl; do
  command -v "$cmd" >/dev/null || { echo "missing: $cmd"; exit 1; }
done
kind get clusters
kubectl cluster-info
df -h / | awk 'NR==2 { if ($5+0 > 80) exit 1 }'
```

预期：所有工具存在，Kind 目标集群可访问，根分区使用率不超过 80%。

- [x] **Step 2：运行完整静态测试。**

```bash
mvn test
helm lint helm/otel-observability
bash tests/helm/test_render.sh
bash tests/helm/test_collector_config.sh
bash tests/helm/test_storage.sh
bash tests/helm/test_grafana.sh
bash tests/scripts/test_minikube_scripts.sh
```

预期：全部退出 0；Maven 为 0 failures/0 errors，Helm 为 0 chart failures。

- [x] **Step 3：先修正 Kind 配置和验证脚本。**

修改 `helm/otel-observability/values-kind.yaml`，删除重复的 `promtail.enabled`，最终只保留 `enabled: true`，并同步修正“禁用 Promtail”和“Loki 无 Service”等过期注释。修改 `scripts/verify-observability.sh`，增加 `VERIFY_APP_URL`、`VERIFY_GRAFANA_URL`、`VERIFY_PROM_URL`、`VERIFY_JAEGER_URL`、`VERIFY_LOKI_URL` 环境变量；五个变量全部提供时不得要求 `minikube`，未提供时保留原 Minikube URL 解析。

在 `tests/scripts/test_minikube_scripts.sh` 增加 help 文本和 URL override 路径断言，在 `tests/helm/test_grafana.sh` 增加 Kind 覆盖值只产生一个 `promtail.enabled` 最终配置的断言。

```bash
bash tests/scripts/test_minikube_scripts.sh
bash tests/helm/test_grafana.sh
```

预期：新增断言修复前失败，修复后退出 0。

- [x] **Step 4：在 Kind 目标环境部署，并启用 Promtail。**

先为 Kind 节点配置足够的 `nofile`，或提供经验证能让 Promtail 正常启动的 Kind 专用配置；随后执行：

```bash
helm upgrade --install otel-observability helm/otel-observability \
  -n observability --create-namespace \
  -f helm/otel-observability/values-minikube.yaml \
  -f helm/otel-observability/values-kind.yaml \
  --set promtail.enabled=true
kubectl get deploy,sts,ds,pods,pvc -n observability
```

不得通过 `promtail.enabled=false` 完成本步骤。如果现有 Kind 节点无法满足限制，应修改 Kind cluster 配置或 Promtail 运行方式，并为修改增加渲染测试。

预期：所有 Deployment、StatefulSet 和 Promtail DaemonSet Ready。

- [x] **Step 5：建立 Kind port-forward 并验证三信号。**

```bash
kubectl port-forward -n observability svc/demo 18080:8080 &
kubectl port-forward -n observability svc/grafana 13000:3000 &
kubectl port-forward -n observability svc/prometheus 19090:9090 &
kubectl port-forward -n observability svc/jaeger 16686:16686 &
kubectl port-forward -n observability svc/loki 13100:3100 &
VERIFY_APP_URL=http://127.0.0.1:18080 \
VERIFY_GRAFANA_URL=http://127.0.0.1:13000 \
VERIFY_PROM_URL=http://127.0.0.1:19090 \
VERIFY_JAEGER_URL=http://127.0.0.1:16686 \
VERIFY_LOKI_URL=http://127.0.0.1:13100 \
  bash scripts/verify-observability.sh
```

预期：

- Demo `/api/hello`、`/api/orders/1001`、`/api/load?count=50` 成功，`/api/error` 返回预期 500。
- Prometheus 查询 `up`、`demo_orders_total`、`demo_errors_total`、`http_server_requests_seconds_count` 成功且有数据。
- Jaeger services 包含 `otel-springboot-demo`。
- Loki 查询 `{namespace="observability",app="otel-springboot-demo"}` 成功且至少有一条日志。
- Grafana 的 Prometheus、Jaeger、Loki 数据源存在。

- [x] **Step 6：记录实际 workload 名并执行重启。**

```bash
kubectl get deploy,sts,ds -n observability \
  -o jsonpath='{range .items[*]}{.kind}/{.metadata.name}{"\n"}{end}'
kubectl rollout restart deployment/demo deployment/otel-collector deployment/grafana \
  -n observability
kubectl delete pod -l app.kubernetes.io/name=prometheus -n observability
kubectl delete pod -l app.kubernetes.io/name=jaeger -n observability
kubectl delete pod -l app.kubernetes.io/name=loki -n observability
kubectl rollout status daemonset/promtail -n observability --timeout=180s
kubectl wait --for=condition=Ready pod \
  -l app.kubernetes.io/part-of=otel-observability \
  -n observability --timeout=180s
```

预期：所有工作负载恢复 Ready。若实际名称不同，必须使用第一条命令返回的名称，不能猜测。

- [x] **Step 7：验证持久化恢复。**

```bash
VERIFY_APP_URL=http://127.0.0.1:18080 \
VERIFY_GRAFANA_URL=http://127.0.0.1:13000 \
VERIFY_PROM_URL=http://127.0.0.1:19090 \
VERIFY_JAEGER_URL=http://127.0.0.1:16686 \
VERIFY_LOKI_URL=http://127.0.0.1:13100 \
  bash scripts/verify-observability.sh
kubectl get pvc -n observability
```

预期：重启后 Prometheus 指标、Jaeger traces 和 Loki logs 仍可查询；PVC 均为 Bound。

- [x] **Step 8：如发现其他缺陷，先添加失败测试，再做最小修复。**

根据缺陷归属选择测试：

```bash
bash tests/helm/test_render.sh
bash tests/helm/test_collector_config.sh
bash tests/helm/test_storage.sh
bash tests/helm/test_grafana.sh
bash tests/scripts/test_minikube_scripts.sh
```

预期：新增断言在修复前失败，修复后与完整测试套件一起通过。

- [x] **Step 9：提交必要修复和验收记录。**

```bash
git status --short
git diff --check
git add helm/otel-observability/values-kind.yaml \
        scripts/verify-observability.sh \
        tests/helm/test_grafana.sh \
        tests/scripts/test_minikube_scripts.sh \
        docs/superpowers/plans/2026-09-06-kind-otel-unified-plan.zh.md
git commit -m "fix: complete observability dynamic verification"
```

如果没有代码缺陷，只更新本计划中的复选框和验证摘要：

```bash
git add docs/superpowers/plans/2026-09-06-kind-otel-unified-plan.zh.md
git commit -m "docs: record observability acceptance results"
```

---

## Kind 组件访问方式

| 组件 | 集群内访问 | Port-forward | 本机访问/检查 |
|---|---|---|---|
| Demo | `http://demo.observability.svc.cluster.local:8080` | `kubectl port-forward -n observability svc/demo 19999:8080` | `http://127.0.0.1:19999/`；健康检查 `/actuator/health` |
| Grafana | `http://grafana.observability.svc.cluster.local:3000` | `kubectl port-forward -n observability svc/grafana 13000:3000` | `http://127.0.0.1:13000`；默认 `admin/admin` |
| Prometheus | `http://prometheus.observability.svc.cluster.local:9090` | `kubectl port-forward -n observability svc/prometheus 19090:9090` | `http://127.0.0.1:19090`；就绪检查 `/-/ready` |
| Jaeger | `http://jaeger.observability.svc.cluster.local:16686` | `kubectl port-forward -n observability svc/jaeger 16686:16686` | `http://127.0.0.1:16686`；API `/api/services` |
| Loki | `http://loki.observability.svc.cluster.local:3100` | `kubectl port-forward -n observability svc/loki 13100:3100` | `http://127.0.0.1:13100`；就绪检查 `/ready` |
| OTel Collector gRPC | `otel-collector.observability.svc.cluster.local:4317` | `kubectl port-forward -n observability svc/otel-collector 4317:4317` | `127.0.0.1:4317`，用于 OTLP/gRPC 客户端 |
| OTel Collector HTTP | `http://otel-collector.observability.svc.cluster.local:4318` | `kubectl port-forward -n observability svc/otel-collector 4318:4318` | `http://127.0.0.1:4318`，用于 OTLP/HTTP 客户端 |
| Promtail | 无需业务 Service | `kubectl port-forward -n observability daemonset/promtail 19080:9080` | `http://127.0.0.1:19080/ready`；日志：`kubectl logs -n observability daemonset/promtail` |

一次建立主要 UI/API 转发：

```bash
kubectl port-forward -n observability svc/demo 19999:8080 &
kubectl port-forward -n observability svc/grafana 13000:3000 &
kubectl port-forward -n observability svc/prometheus 19090:9090 &
kubectl port-forward -n observability svc/jaeger 16686:16686 &
kubectl port-forward -n observability svc/loki 13100:3100 &
```

Kind 节点若仍使用默认 `fs.inotify.max_user_instances=128`，启动 Promtail 前执行：

```bash
docker exec migration-control-plane sysctl -w fs.inotify.max_user_instances=1024
```

该命令修改共享内核参数；需要恢复时执行同一命令并设为 `128`。

## 最终验收记录

### 已有记录

- 2026-09-06 静态复验：Maven 5 tests、0 failures、0 errors；Helm lint 0 failures；render、collector、storage、Grafana 和脚本测试退出码均为 0。
- 历史 Kind 验证：Demo、Prometheus、Jaeger、Grafana 成功；Loki workload 运行但无日志；Promtail 因 Kind containerd `nofile` 限制被禁用或无法正常启动。
- 2026-09-07 当前验收：Kind v0.24.0，context `kind-migration`，Kubernetes Server v1.31.0，Helm revision 6 状态 `deployed`；七个工作负载全部 Ready。
- 三信号验证：Prometheus、Jaeger、Loki 和 Grafana 3/3 数据源通过；Promtail 采集 Demo 日志。
- 持久化恢复：重启全部 Deployment、StatefulSet Pod 和 DaemonSet 后，`demo_orders_total=153`、trace `6a37292fcf322044cfbaf1728e4b815d`、5 条既有 Loki 日志仍可查询；四个 PVC 保持 Bound。
- 环境修正：共享内核 `fs.inotify.max_user_instances` 从 128 临时提升至 1024；实际阻塞并非无效的 PodSecurityContext `nofile` 字段。

### 待补记录

- [x] 动态验收日期和 Kubernetes 类型/版本。
- [x] Promtail Ready 证据。
- [x] Loki 返回应用日志证据。
- [x] 重启前后 metrics、traces、logs 查询摘要。
- [x] PVC Bound 状态及恢复结论。
- [x] 最终提交：已直接提交到 `main`，实现提交 `e08e780`。

## 整体完成标准

只有以下全部成立时，本计划才能标记为“全部完成”：

- [x] Tasks 1–6 的实现和静态测试存在并已合入 `main`。
- [x] Kind 环境完成 Demo、metrics、traces 和 Grafana 的历史端到端验证。
- [x] Promtail Ready，Loki 可以查询到 Demo 应用日志。
- [x] Prometheus、Jaeger、Loki 在 Pod 重启后保留并返回既有数据。
- [x] Task 8 的动态验证命令全部退出 0。
- [x] 最终验收记录已写回本文件；文档收口提交后工作树干净。

## 安全回滚与清理

- 默认只执行 `helm uninstall otel-observability -n observability`，不得删除 PVC 或 Kind 集群。
- 只有用户明确要求删除数据时，才删除 `observability` 命名空间内属于本 release 的 PVC。
- 只有用户明确要求删除目标集群时，才执行 `kind delete cluster --name kind-migration`。
- 不得停止或删除无关 Kind cluster 或 namespace。
- 代码修复优先使用 `git revert 4e57fe9`；不得使用会丢失用户改动的 `git reset --hard`。

## 历史资料

- `docs/superpowers/specs/2026-08-01-minikube-opentelemetry-observability-design.md`
- `docs/superpowers/plans/2026-08-02-minikube-opentelemetry-implementation.md`
- `docs/superpowers/plans/2026-09-04-continue-execution.md`
- `docs/superpowers/plans/2026-09-04-continue-execution.zh.md`
- `docs/superpowers/plans/2026-09-04-audit-report.md`

本文件是后续执行与验收的主要入口；历史文件只用于追溯决策和原始上下文。
