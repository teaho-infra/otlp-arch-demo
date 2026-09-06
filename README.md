# OpenTelemetry Spring Boot Demo

这个目录包含一个可运行的 Java 8 / Spring Boot 2.7 demo，用来演示 OpenTelemetry 从应用采集、Collector 汇聚、Prometheus 存储到 Grafana 展示的完整链路。

## 链路结构

```text
Spring Boot App
  |  OTLP traces / metrics / logs, via OpenTelemetry Java Agent
  v
OpenTelemetry Collector
  |  prometheus exporter :8889
  v
Prometheus
  v
Grafana
```

同时 Prometheus 也会直接抓取 Spring Boot Actuator 的 `/actuator/prometheus`，方便对比 Micrometer 指标和 OTel 指标。

## 本地运行

先构建应用：

```bash
mvn clean package
```

启动完整链路：

```bash
docker compose up --build
```

访问地址：

- App: http://localhost:18080
- App metrics: http://localhost:18080/actuator/prometheus
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3000，账号密码都是 `admin`

Grafana 启动后会自动加载 `OpenTelemetry / OpenTelemetry Spring Boot Demo` dashboard。

## 产生测试流量

```bash
curl http://localhost:18080/api/hello
curl http://localhost:18080/api/orders/1001
curl "http://localhost:18080/api/load?count=50"
curl http://localhost:18080/api/error
```

`/api/error` 会故意返回 500，用于验证错误追踪和错误指标。

## 关键文件

- `src/main/java/com/example/otel/DemoController.java`: 业务接口和自定义 OpenTelemetry 指标。
- `Dockerfile`: 将 OpenTelemetry Java Agent 放入应用镜像。
- `docker-compose.yml`: 启动 App、Collector、Prometheus、Grafana。
- `otel-collector-config.yml`: 接收 OTLP 并导出指标到 Prometheus。
- `prometheus/prometheus.yml`: 抓取 Collector 和 Spring Boot Actuator。
- `grafana/`: 自动配置 Prometheus 数据源和 dashboard。

## 常用排查

查看 Collector 是否收到 trace / metric：

```bash
docker compose logs -f otel-collector
```

在 Prometheus 查询：

```promql
up
demo_orders_total
http_server_requests_seconds_count
```

如果 `demo_orders_total` 没有数据，先请求 `/api/orders/1001` 或 `/api/load?count=50`，再等待 5 到 10 秒。

如果你希望宿主机仍然使用 8080 端口，可以这样启动：

```bash
APP_PORT=8080 docker compose up --build
```

## 在 Minikube 上运行 (推荐)

`docker compose` 适合单节点测试。**推荐在 Minikube 上跑**以获得完整的 Kubernetes
体验（Promtail DaemonSet 抓取、StatefulSet PVC、Loki query_range、Jaeger OTLP 等）。

仓库在 `feature/minikube-otel-cluster` 分支提供了一个 umbrella Helm chart，
把 demo + collector + Prometheus + Grafana + Jaeger + Loki + Promtail 全部装进
`observability` namespace。

前置：minikube / kubectl / helm / mvn / docker（参见 `helm/otel-observability/README.md`）。

```bash
# 启动（自动起 minikube 集群、build image、helm install）
git checkout feature/minikube-otel-cluster
./scripts/minikube-up.sh

# 端到端验证 HTTP / Prometheus / Jaeger / Loki / Grafana
./scripts/verify-observability.sh

# 清理（保留 Minikube 集群和 PVC 数据）
./scripts/minikube-down.sh

# 清理 + 删 PVC（数据丢失）
./scripts/minikube-down.sh --delete-data
```

安装完会打印所有 service 的 NodePort URL。详细故障排查参见
`helm/otel-observability/README.md` 和 `tests/integration/README.md`。

## 关键文件

- `src/main/java/com/example/otel/DemoController.java`: 业务接口和自定义 OpenTelemetry 指标。
- `Dockerfile`: 将 OpenTelemetry Java Agent 放入应用镜像。
- `docker-compose.yml`: 启动 App、Collector、Prometheus、Grafana（**仅作参考**，推荐用 Helm + Minikube）。
- `otel-collector-config.yml`: 接收 OTLP 并导出指标到 Prometheus。
- `prometheus/prometheus.yml`: 抓取 Collector 和 Spring Boot Actuator。
- `grafana/`: 自动配置 Prometheus 数据源和 dashboard。
- `helm/otel-observability/`: 在 Minikube 上跑的 umbrella Helm chart。
- `scripts/`: Minikube 生命周期和验证脚本（仅在 `feature/minikube-otel-cluster` 分支）。
- `docs/superpowers/plans/`: 实施计划和审计报告。
