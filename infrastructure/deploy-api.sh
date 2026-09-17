#!/usr/bin/env bash
#
# Provisions only the Function App for the daily revenue/COGS/net dashboard's
# API, wired up to an already-provisioned storage account (CSV blobs) and
# Azure Cache for Redis (see deploy.sh, which provisions those). Use this to
# (re)provision just the backend compute without touching the existing
# storage/Redis/Static Web App. To build and push the api into the Function
# App, run release.sh afterward with the RG/FUNCAPP names printed at the end
# of this script.
#
# Requires: az CLI, already logged in (`az login`) with the target
# subscription selected (`az account set --subscription <id>`).
#
# Usage:
#   RG=rg-daily-metrics-dashboard STORAGE=stdailymetricsabc123 \
#     REDIS=redis-daily-metrics-abc123 ./deploy-api.sh

set -euo pipefail

RG="${RG:?RG must be set to the resource group of the existing storage account/Redis cache}"
STORAGE="${STORAGE:?STORAGE must be set to the existing storage account name (CSV blobs)}"
REDIS="${REDIS:?REDIS must be set to the existing Azure Cache for Redis name}"
LOCATION="${LOCATION:-eastus}"
SUFFIX="${SUFFIX:-$(openssl rand -hex 3)}"          # globally-unique name suffix
FUNCAPP="${FUNCAPP:-func-daily-metrics-$SUFFIX}"

if ! command -v az >/dev/null 2>&1; then
  echo "Error: az CLI not found. Install the Azure CLI first." >&2
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  echo "Error: not logged in to Azure CLI. Run 'az login' first." >&2
  exit 1
fi

echo "==> Function App: $FUNCAPP"
az functionapp create \
  --name "$FUNCAPP" --resource-group "$RG" \
  --consumption-plan-location "$LOCATION" \
  --runtime node --runtime-version 24 --functions-version 4 \
  --storage-account "$STORAGE" --output none

echo "==> Wiring CSV storage connection into Function App"
STORAGE_CONN=$(az storage account show-connection-string \
  --name "$STORAGE" --resource-group "$RG" --query connectionString -o tsv)

az functionapp config appsettings set \
  --name "$FUNCAPP" --resource-group "$RG" \
  --settings "CSV_STORAGE_CONNECTION=$STORAGE_CONN" --output none

echo "==> Wiring Redis connection into Function App"
REDIS_KEY=$(az redis list-keys \
  --name "$REDIS" --resource-group "$RG" --query primaryKey -o tsv)
REDIS_HOST=$(az redis show \
  --name "$REDIS" --resource-group "$RG" --query hostName -o tsv)

az functionapp config appsettings set \
  --name "$FUNCAPP" --resource-group "$RG" \
  --settings "REDIS_CONNECTION_STRING=rediss://:$REDIS_KEY@$REDIS_HOST:6380" --output none

cat <<EOF

==> Done. Provisioned resources:
    Resource group:   $RG
    Function App:     $FUNCAPP

    To build and deploy the api into this Function App, run:
      RG=$RG FUNCAPP=$FUNCAPP ./release.sh
EOF
