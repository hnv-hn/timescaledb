#!/bin/bash
# Restore helper for timescaledb (hetida_ts database).
# Requires kubectl access and secrets/s3-creds in target namespace.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
RECOVERY_DIR="${REPO_ROOT}/k8s/recovery"

TARGET="${RESTORE_TARGET:-dev}"
OVERLAY_DIR="${REPO_ROOT}/k8s/overlays/${TARGET}"

# Default namespace from matching overlay (overlays/dev or overlays/prod kustomization.yaml)
if [[ -z "${NAMESPACE:-}" ]]; then
  if [[ -f "${OVERLAY_DIR}/kustomization.yaml" ]]; then
    NAMESPACE="$(grep '^namespace:' "${OVERLAY_DIR}/kustomization.yaml" | awk '{print $2}')"
  fi
  NAMESPACE="${NAMESPACE:-hetida-platform-dev}"
fi

MODE="${1:-}"
TIMESTAMP="${2:-}"

usage() {
  echo "Usage:"
  echo "  $0 latest                         # latest backup (RESTORE_TARGET=dev → MinIO)"
  echo "  RESTORE_TARGET=prod $0 latest     # latest backup from prod S3 manifest"
  echo "  $0 pitr '2026-05-06T14:30:00Z'"
  echo "  $0 test                           # apply restore-test.yaml"
  echo ""
  echo "Environment:"
  echo "  NAMESPACE          target namespace (default: from k8s/overlays/<RESTORE_TARGET>/kustomization.yaml)"
  echo "  RESTORE_TARGET     dev | prod (default: dev)"
  echo ""
  echo "Examples:"
  echo "  NAMESPACE=hetida-platform-dev $0 latest"
  echo "  RESTORE_TARGET=prod NAMESPACE=hetida-platform-prod $0 latest"
  exit 1
}

apply_manifest() {
  local file="$1"
  sed "s/^  namespace: .*/  namespace: ${NAMESPACE}/" "$file" | kubectl apply -n "$NAMESPACE" -f -
}

[[ -z "$MODE" ]] && usage

echo "Restore mode: $MODE (namespace: $NAMESPACE, target: $TARGET)"
cd "$RECOVERY_DIR"

case "$MODE" in
  latest)
    if [[ "$TARGET" == "prod" ]]; then
      apply_manifest restore-latest-prod.yaml
    else
      apply_manifest restore-latest.yaml
    fi
    ;;
  pitr)
    [[ -z "$TIMESTAMP" ]] && { echo "Missing timestamp for pitr"; usage; }
    sed -e "s/^  namespace: .*/  namespace: ${NAMESPACE}/" \
      -e "s/targetTime: '.*'/targetTime: '${TIMESTAMP}'/" \
      restore-timestamp.yaml | kubectl apply -n "$NAMESPACE" -f -
    ;;
  test)
    apply_manifest restore-test.yaml
    ;;
  *)
    usage
    ;;
esac

echo "Restore cluster submitted. Watch: kubectl get cluster -n $NAMESPACE -w"
