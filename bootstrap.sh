#!/usr/bin/env bash
# Bootstrap shared Docker infrastructure for the Lab F 11+ suite.
#
# Creates labf-net (shared bridge network) and labf-db (shared PostgreSQL).
# Idempotent — safe to re-run. Already-existing resources are left alone.
#
# Usage:
#   ./bootstrap.sh
#
# Override the network name or DB password via env vars (rarely needed):
#   LABF_NETWORK=other-net ./bootstrap.sh
#   DB_PASSWORD=something-else ./bootstrap.sh

set -euo pipefail

NETWORK_NAME="${LABF_NETWORK:-labf-net}"
DB_PASSWORD="${DB_PASSWORD:-hub_dev_password}"

if ! command -v docker >/dev/null 2>&1; then
  echo "bootstrap: docker not found on PATH" >&2
  exit 1
fi

# --- Shared network ---
if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  echo "bootstrap: network '$NETWORK_NAME' already exists, leaving it alone."
else
  echo "bootstrap: creating network '$NETWORK_NAME'..."
  docker network create "$NETWORK_NAME" >/dev/null
  echo "bootstrap: network '$NETWORK_NAME' created."
fi

# --- Shared PostgreSQL ---
export DB_PASSWORD
docker compose up -d

echo "bootstrap: shared infra ready (labf-net + labf-db)."
