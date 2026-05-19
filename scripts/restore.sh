#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECOVERY_DIR="$SCRIPT_DIR/../k8s/recovery"

MODE=$1
TIMESTAMP=$2

echo "🚀 Starting restore..."

if [ "$MODE" == "latest" ]; then
  kubectl apply -f restore-latest.yaml

elif [ "$MODE" == "pitr" ]; then
  if [ -z "$TIMESTAMP" ]; then
    echo "❌ Please provide timestamp"
    exit 1
  fi

  sed "s/TIMESTAMP/$TIMESTAMP/" restore-timestamp.yaml | kubectl apply -f -

elif [ "$MODE" == "test" ]; then
  kubectl apply -f restore-test.yaml

else
  echo "Usage:"
  echo "  ./restore.sh latest"
  echo "  ./restore.sh pitr '2026-05-06 02:30:00'"
  echo "  ./restore.sh test"
  exit 1
fi

echo "✅ Restore triggered"
