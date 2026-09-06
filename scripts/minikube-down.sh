#!/usr/bin/env bash
# Tear down the otel-observability Helm release from Minikube.
#
# By default, this only uninstalls the release and leaves PVCs / Minikube
# running. Pass --delete-data to additionally delete the namespace's
# PVCs (data is irrecoverable once removed).
#
# Never stops or deletes the Minikube cluster itself.
#
# Usage: scripts/minikube-down.sh [--delete-data] [--help]
set -euo pipefail

usage() {
  cat <<EOF
Usage: scripts/minikube-down.sh [--delete-data] [--help]

Uninstalls the otel-observability Helm release from Minikube.

  --delete-data   Also delete the namespace's PVCs (irrecoverable).
  --help, -h      Show this help.

By default only the release is uninstalled; the Minikube cluster and any
PersistentVolumeClaims are left untouched.
EOF
}

delete_data=false
case "${1:-}" in
  "") ;;
  --delete-data) delete_data=true ;;
  -h|--help) usage; exit 0 ;;
  *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac

command -v helm >/dev/null || { echo "error: helm is required" >&2; exit 1; }
command -v kubectl >/dev/null || { echo "error: kubectl is required" >&2; exit 1; }

# Refuse to delete Minikube itself, ever.
echo "uninstalling otel-observability release..."
helm uninstall otel-observability -n observability --ignore-not-found

if $delete_data; then
  echo "deleting PVCs in observability namespace..."
  kubectl delete pvc --all -n observability --ignore-not-found
fi

echo "done. Minikube cluster left running."
