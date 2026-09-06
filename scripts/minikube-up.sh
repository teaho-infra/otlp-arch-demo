#!/usr/bin/env bash
# Bring up the Minikube cluster, build the Spring Boot demo image, and
# install or upgrade the otel-observability Helm chart into the
# `observability` namespace. Prints each service URL when done.
#
# Usage: scripts/minikube-up.sh [--help]
set -euo pipefail

usage() {
  cat <<EOF
Usage: scripts/minikube-up.sh [--help]

Starts (or reuses) a Minikube cluster, builds otel-springboot-demo:local,
and installs/upgrade the otel-observability chart into the observability
namespace. Waits for every workload (Deployment + StatefulSet + DaemonSet)
to become Ready before printing service URLs.

Required tools: minikube, kubectl, helm, mvn, docker.
EOF
}
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then usage; exit 0; fi
if [[ $# -ne 0 ]]; then echo "error: unknown argument: $1" >&2; usage >&2; exit 2; fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
chart="$repo_root/helm/otel-observability"

# On failure, leave Minikube and the cluster state intact for debugging.
trap 'echo "minikube-up failed; minikube + release are left in place for debugging" >&2' ERR

for cmd in minikube kubectl helm mvn docker; do
  command -v "$cmd" >/dev/null || { echo "error: $cmd is required" >&2; exit 1; }
done

# 1. Cluster.
minikube start --cpus=6 --memory=8192

# 2. Image build inside Minikube's Docker daemon.
eval "$(minikube docker-env)"
mvn -B -f "$repo_root/pom.xml" -DskipTests clean package
docker build -t otel-springboot-demo:local "$repo_root"

# 3. Lint + install.
helm lint "$chart"
helm upgrade --install otel-observability "$chart" \
  --create-namespace \
  -n observability \
  -f "$chart/values-minikube.yaml"

# 4. Readiness for every workload kind. We do not hardcode the demo
#    Deployment name — Helm may prefix it with the release + chart name.
#    Find it by label instead.
echo "waiting for workloads..."

kubectl wait --for=condition=Ready pod \
  -l app.kubernetes.io/instance=otel-observability \
  -n observability --timeout=180s

# 5. Print URLs.
echo
echo "service URLs (open in browser):"
for service in demo grafana prometheus jaeger loki; do
  url="$(minikube service "$service" -n observability --url 2>/dev/null | head -n 1 || true)"
  if [[ -n "$url" ]]; then
    printf "  %-12s %s\n" "$service" "$url"
  else
    printf "  %-12s (URL unavailable)\n" "$service"
  fi
done

echo
echo "observability stack is up. Run scripts/verify-observability.sh to confirm."
