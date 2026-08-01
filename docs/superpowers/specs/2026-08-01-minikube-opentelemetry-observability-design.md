# Minikube OpenTelemetry 本地观测集群设计

## 1. 目标与范围

在 Minikube 中部署一套可重复安装的本地 OpenTelemetry 观测集群，并跑通 Java 8、Spring Boot 2.7 Demo 的指标、Trace 和日志采集、处理、存储、查询及关联。

一期范围包括：

- Spring Boot 2.7.18 / JDK 8 Demo。
- OpenTelemetry Java Agent 自动采集 HTTP、JVM 和应用遥测数据。
- OpenTelemetry Collector 接收 OTLP，执行批处理、内存保护、资源属性处理、重试和路由导出。
- Prometheus 指标存储、Recording Rules 和基础告警规则。
- Jaeger Trace 存储与查询。
- Loki 日志存储，Promtail 采集 Kubernetes 容器日志。
- Grafana 统一查询、Dashboard、数据源预置以及 Trace/Log/Metric 关联。
- 一个自包含的 Umbrella Helm Chart、Minikube 部署脚本、端到端验证脚本和排障文档。

不包含 Kubernetes Operator、多节点高可用、离线镜像仓库和生产级安全加固。Docker Compose 可作为已有配置的参考，但最终部署入口是 Helm + Minikube。

## 2. 整体架构与数据流

```text
Spring Boot 2.7 / JDK 8 Demo
  ├─ OTel Java Agent
  │    ├─ OTLP traces
  │    ├─ OTLP metrics
  │    └─ OTLP logs
  v
OpenTelemetry Collector
  ├─ traces ──> Jaeger ──> Grafana
  ├─ metrics ─> Prometheus ─> Grafana
  └─ logs ────> Loki ───────> Grafana

Kubernetes container logs ──> Promtail ──> Loki
```

应用通过 Kubernetes Service 访问 Collector：

- OTLP gRPC：`otel-collector:4317`
- OTLP HTTP：`otel-collector:4318`

Collector 使用三条独立 pipeline：traces、metrics、logs。每条 pipeline 使用 `memory_limiter`、资源属性处理、`batch`、retry/sending queue，并分别导出到 Jaeger、Prometheus 和 Loki。Collector 不强依赖后端启动，后端短暂不可用时由重试机制处理。

Grafana 预置 Prometheus、Jaeger、Loki 三个数据源，并配置 Trace 到日志、日志到 Trace 的关联字段和跳转链接。

## 3. Helm Chart 设计

Chart 路径为 `helm/otel-observability/`：

```text
helm/otel-observability/
├── Chart.yaml
├── values.yaml
├── values-minikube.yaml
├── templates/
│   ├── namespace.yaml
│   ├── app-deployment.yaml
│   ├── app-service.yaml
│   ├── collector-configmap.yaml
│   ├── collector-deployment.yaml
│   ├── collector-service.yaml
│   ├── prometheus-configmap.yaml
│   ├── prometheus-rules-configmap.yaml
│   ├── prometheus-statefulset.yaml
│   ├── prometheus-service.yaml
│   ├── grafana-configmaps.yaml
│   ├── grafana-deployment.yaml
│   ├── grafana-service.yaml
│   ├── jaeger-statefulset.yaml
│   ├── jaeger-service.yaml
│   ├── loki-statefulset.yaml
│   ├── loki-service.yaml
│   ├── promtail-daemonset.yaml
│   ├── pvc.yaml
│   ├── ingress.yaml
│   └── _helpers.tpl
└── README.md
```

Chart 自己管理所有组件，不依赖外部 Helm Repository。`values.yaml` 提供通用默认值，`values-minikube.yaml` 提供低资源本地配置。镜像版本、端口、资源限制、PVC 大小、NodePort、保留周期和组件开关均可通过 values 调整。

默认命名空间为 `observability`。组件开关包括 `promtail.enabled`、`ingress.enabled` 和 `persistence.enabled`。默认开启持久化。默认使用 NodePort 访问；启用 Ingress 后使用 `grafana.otel.local`、`prometheus.otel.local`、`jaeger.otel.local` 和 `demo.otel.local`。

推荐操作流程：

```bash
minikube start --cpus=6 --memory=8192
eval $(minikube docker-env)
mvn clean package
docker build -t otel-springboot-demo:local .
helm lint helm/otel-observability
helm template otel-observability helm/otel-observability \
  -f helm/otel-observability/values-minikube.yaml
helm upgrade --install otel-observability helm/otel-observability \
  -f helm/otel-observability/values-minikube.yaml \
  --create-namespace -n observability
```

## 4. 存储、保留与资源

所有核心存储组件使用 Minikube 默认 `standard` StorageClass 的 PVC：

| 组件 | 存储方式 | 默认容量 | 默认保留 |
|---|---|---:|---:|
| Prometheus | TSDB PVC | 5Gi | 7 天 |
| Jaeger | Badger/本地 PVC | 5Gi | 7 天 |
| Loki | filesystem PVC | 5Gi | 7 天 |
| Grafana | SQLite PVC | 1Gi | 配置和 Dashboard |
| Promtail | 无 PVC | — | 发送端 |

通过 `persistence.enabled=false` 可切换为临时模式。Prometheus、Jaeger 和 Loki 配置 retention，避免本地磁盘持续增长。

Minikube 默认资源预算：6 CPU、8GiB 内存、至少 20GiB 磁盘。组件初始资源限制如下：

- Demo：100m–500m CPU，256Mi–512Mi 内存。
- Collector：100m–500m CPU，256Mi–512Mi 内存。
- Prometheus：200m–800m CPU，512Mi–1Gi 内存。
- Grafana：100m–500m CPU，256Mi–512Mi 内存。
- Jaeger：100m–500m CPU，256Mi–512Mi 内存。
- Loki：100m–500m CPU，256Mi–512Mi 内存。
- Promtail：每节点 50m–200m CPU，64Mi–128Mi 内存。

## 5. Demo 应用与遥测契约

Demo 保持 Java 8、Spring Boot 2.7.18、Spring MVC、Actuator、Micrometer Prometheus 和 OpenTelemetry API。应用镜像启动时通过 `JAVA_TOOL_OPTIONS` 注入 OTel Java Agent，并设置 `OTEL_SERVICE_NAME`、`OTEL_RESOURCE_ATTRIBUTES`、OTEL OTLP endpoint、协议以及 traces/metrics/logs exporter。

接口包括：

- `/api/hello`：正常请求，验证 HTTP Trace。
- `/api/orders/{id}`：生成订单计数和处理延迟 Histogram。
- `/api/load?count=50`：批量生成指标和 Trace。
- `/api/error`：返回 500，验证错误 Trace、指标和日志。
- `/actuator/prometheus`：保留 Micrometer 指标。
- `/actuator/health`：用于 Kubernetes 探针。

自定义指标为 `demo_orders_total`、`demo_errors_total` 和 `demo_order_latency`。指标只使用 `status`、`route`、`service.name`、`deployment.environment` 等低基数标签，不使用订单 ID 和请求 ID。

应用日志输出到 stdout，Promtail 采集 Kubernetes 容器日志发送到 Loki；Collector OTLP logs pipeline 作为结构化 OTel 日志的统一入口。日志保留正文和基础 Kubernetes 标签，不把请求 ID、订单 ID 等高基数字段设为 Loki 索引标签。

## 6. Prometheus 规则与 Grafana

Prometheus 配置 recording rules，预计算 HTTP 请求速率、HTTP 错误率、HTTP P95 延迟、Demo 订单处理速率和 Collector 接收/丢弃数据量。

基础告警包括 Demo 服务不可用、Collector 不可用、HTTP 5xx 比例过高、HTTP P95 延迟过高、Collector exporter 发送失败和 Prometheus target down。

Grafana Dashboard 展示请求速率、5xx 错误率、P95 延迟、JVM 内存、JVM 线程、Collector 接收/发送状态、Trace 服务列表和 Loki 应用日志，并配置 Trace/Log 关联。

## 7. 探针、故障处理与安全边界

所有 Deployment、StatefulSet 和 DaemonSet 配置 readiness/liveness probes。Collector 配置错误时 Pod 不 Ready；PVC 挂载失败时存储组件保持 Pending；后端短暂不可用时 Collector 使用 retry 和 sending queue；组件 OOM 时通过资源限制和 retention 降低影响范围；Promtail 故障只影响日志链路，不阻塞指标和 Trace。

所有组件提供 `kubectl logs`、`kubectl describe`、Collector self-metrics 和 Prometheus targets 排查路径。默认使用本地 Demo 凭据和 NodePort，适用于本地环境，不作为生产安全配置。

## 8. 验证方案

测试分层：

1. 静态检查：`helm lint`、`helm template`、YAML 语法检查和 Collector 配置结构检查。
2. Java 测试：`mvn test`、Spring Context 加载和 Demo 接口基本行为测试。
3. 镜像测试：Java 8 编译、Demo 镜像构建和 Agent 文件存在性检查。
4. Minikube 集成测试：安装 Chart，等待全部工作负载 Ready，访问 Demo，查询 Prometheus、Jaeger、Loki，验证 Grafana Provisioning 和 Trace/Metric/Log 关联。
5. 重启恢复测试：重建 Demo/Collector/Prometheus/Jaeger/Loki Pod，确认 PVC 数据仍可读取。

验收流量：

```bash
curl http://demo/api/hello
curl http://demo/api/orders/1001
curl "http://demo/api/load?count=50"
curl http://demo/api/error
```

验收必须确认：所有 Pod Ready；Collector 无持续 exporter error；Prometheus 能查询 `up`、`demo_orders_total`、`demo_errors_total` 和 `http_server_requests_seconds_count`；Jaeger 能看到 `otel-springboot-demo` 和错误 Trace；Loki 能查询 `{namespace="observability", app="otel-springboot-demo"}`；Grafana Dashboard 有数据且 Trace 与日志可以互跳。

## 9. 交付物

```text
helm/otel-observability/        # 完整 Umbrella Chart
scripts/minikube-up.sh          # 创建 Minikube 并部署
scripts/minikube-down.sh        # 卸载 Chart，可选删除 PVC
scripts/verify-observability.sh # 端到端验收
docs/                           # 部署、排障和数据流文档
README.md                       # 快速开始
```

README 和 Chart README 记录架构、Minikube 资源要求、安装/升级/卸载、本地镜像、访问地址、PromQL、LogQL、故障排查、PVC/保留周期、JDK 8/Spring Boot 2.7 兼容性和验收预期输出。
