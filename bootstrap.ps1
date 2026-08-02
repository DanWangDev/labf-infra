# Bootstrap shared Docker infrastructure for the Lab F 11+ suite (Windows).
#
# Creates labf-net (shared bridge network) and labf-db (shared PostgreSQL).
# Idempotent — safe to re-run.
#
# Usage:
#   .\bootstrap.ps1

$ErrorActionPreference = "Stop"

$networkName = if ($env:LABF_NETWORK) { $env:LABF_NETWORK } else { "labf-net" }
$dbPassword = if ($env:DB_PASSWORD) { $env:DB_PASSWORD } else { "hub_dev_password" }

# --- Shared network ---
$existing = docker network inspect $networkName 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "bootstrap: network '$networkName' already exists, leaving it alone."
} else {
    Write-Host "bootstrap: creating network '$networkName'..."
    docker network create $networkName | Out-Null
    Write-Host "bootstrap: network '$networkName' created."
}

# --- Shared PostgreSQL ---
$env:DB_PASSWORD = $dbPassword
docker compose up -d

Write-Host "bootstrap: shared infra ready (labf-net + labf-db)."
