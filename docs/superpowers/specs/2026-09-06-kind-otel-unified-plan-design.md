# Kind OpenTelemetry 中文统一计划设计

## 目的

把现有实施计划、继续执行计划、审计报告和 Hermes 在 Kind 集群上的验证结果整理为一份中文权威计划。新计划反映仓库的真实完成状态，同时保留尚未满足的验收要求，并以 Kind 作为目标部署环境。

## 文档关系

- 新计划保存为 `docs/superpowers/plans/2026-09-06-kind-otel-unified-plan.zh.md`。
- 旧计划和审计报告保留为历史资料，不删除、不覆盖。
- 新计划成为后续执行和验收的主要入口，并链接旧文档以便追溯。

## 状态表达

- 已有提交、当前源码和测试能够证明完成的步骤标记为 `[x]`。
- Hermes 在 Kind 集群上实际验证过的项目标记为 `[x]`，同时注明环境、结果和限制。
- 未在 Kind 目标环境证明完成的项目保持 `[ ]`，不能用静态渲染测试或历史的部分结果替代。
- Git 提交只能证明实现或历史验证发生过；对当前可运行状态的声明必须附新鲜验证命令和结果。

## 计划结构

统一计划按以下顺序组织：

1. 目标、架构、技术栈和全局约束。
2. 当前状态总览和证据规则。
3. Tasks 1–6 的实现步骤、提交证据和完成状态。
4. Task 7 的 Kind 端到端验证结果，包括成功项和 Promtail/Loki 限制。
5. 剩余验收：支持 Promtail 的环境验证、日志链路、PVC 持久化恢复和最终记录更新。
6. 最终完成标准、验证命令、回滚及交接要求。

## Kind 验证的边界

Kind 验证可以证明 Demo、Prometheus、Jaeger、Grafana 和主要 Chart 部署链路曾经工作。历史验证时 Promtail 被禁用且 Loki 没有采集到应用日志，因此当时不能证明日志链路或 PVC 重启恢复完成。Task 8 已在当前 Kind 集群补齐这两项动态验收。

## 完成标准

统一计划只有在以下条件全部满足后才能整体标记完成：

- 单元、Helm 渲染和脚本测试全部通过。
- 在 Kind 环境中解决 Promtail 的 inotify instance 限制，并验证 metrics、traces、logs 和 Grafana 数据源/仪表盘。
- 重启相关 Deployment、StatefulSet 和 DaemonSet 后，持久化数据仍可查询。
- 最终验证环境、命令摘要、限制和提交状态写回统一计划。

## 组件访问设计

Kind 部署默认使用 ClusterIP，不直接暴露宿主机端口。交互式访问统一使用 `kubectl port-forward -n observability`：Demo `svc/demo:8080`、Grafana `svc/grafana:3000`、Prometheus `svc/prometheus:9090`、Jaeger `svc/jaeger:16686`、Loki `svc/loki:3100`。Collector 仅供遥测发送，集群内使用 `otel-collector.observability.svc.cluster.local:4317/4318`；需要宿主机调试时分别转发 4317 和 4318。Promtail 没有用户界面，通过 `kubectl logs -n observability daemonset/promtail` 和 `kubectl port-forward -n observability daemonset/promtail 19080:9080` 检查。

统一计划必须给出每个组件的集群内地址、port-forward 命令、本机 URL、Grafana 默认凭据和健康/查询入口。

## 范围限制

初始阶段只整合计划文档；经用户批准执行 Task 8 后，允许修改 Helm Chart、验证脚本和测试，并在现有 Kind 集群部署验证。历史文档和无关集群不得删除。
