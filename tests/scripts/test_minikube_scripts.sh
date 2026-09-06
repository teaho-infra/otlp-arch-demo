#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for script in minikube-up.sh minikube-down.sh verify-observability.sh; do "$repo_root/scripts/$script" --help >/dev/null; done
if "$repo_root/scripts/minikube-down.sh" --unexpected >/dev/null 2>&1; then exit 1; fi
if "$repo_root/scripts/minikube-up.sh" --unexpected >/dev/null 2>&1; then exit 1; fi
