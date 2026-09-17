#!/usr/bin/env bash
#
# Provisions the Azure resources for the daily revenue/COGS/net dashboard,
# per docs/superpowers/specs/2026-09-17-daily-metrics-dashboard-design.md
# ("Azure resource provisioning (Azure CLI)"). Creates infrastructure only —
# to build and push the web-client into the Static Web App, run
# release.sh afterward with the RG/SWA names printed at the end of this
# script.
#
# Requires: az CLI, already logged in (`az login`) with the target
# subscription selected (`az account set --subscription <id>`).

set -euo pipefail

# --- variables (override any of these via environment) ---
RG="${RG:-rg-daily-metrics-dashboard}"
LOCATION="${LOCATION:-centralus}"
SUFFIX="${SUFFIX:-$(openssl rand -hex 3)}"          # globally-unique name suffix
STORAGE="${STORAGE:-stdailymetrics$SUFFIX}"
CONTAINER="${CONTAINER:-csv-data}"
REDIS="${REDIS:-redis-daily-metrics-$SUFFIX}"
FUNCAPP="${FUNCAPP:-func-daily-metrics-$SUFFIX}"
SWA="${SWA:-swa-daily-metrics-$SUFFIX}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
APP_LOCATION="${APP_LOCATION:-web-client}"
OUTPUT_LOCATION="${OUTPUT_LOCATION:-dist}"
GITHUB_REPO="${GITHUB_REPO:-https://github.com/datafabriq-co/prototype}"

if ! command -v az >/dev/null 2>&1; then
  echo "Error: az CLI not found. Install the Azure CLI first." >&2
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  echo "Error: not logged in to Azure CLI. Run 'az login' first." >&2
  exit 1
fi

if ! az extension show --name staticwebapp >/dev/null 2>&1; then
  echo "==> Installing az staticwebapp extension"
  az extension add --name staticwebapp
fi

echo "==> Resource group: $RG ($LOCATION)"
az group create --name "$RG" --location "$LOCATION" --output none

echo "==> Storage account: $STORAGE"
if az storage account show --name "$STORAGE" --resource-group "$RG" --output none 2>/dev/null; then
  echo "    already exists, skipping"
  STORAGE_CREATED=false
else
  az storage account create \
    --name "$STORAGE" --resource-group "$RG" --location "$LOCATION" \
    --sku Standard_LRS --kind StorageV2 --output none
  STORAGE_CREATED=true
fi

echo "==> Blob container: $CONTAINER"
if [ "$(az storage container exists \
  --name "$CONTAINER" --account-name "$STORAGE" --auth-mode login --query exists -o tsv 2>/dev/null)" = "true" ]; then
  echo "    already exists, skipping"
elif ! az storage container create \
  --name "$CONTAINER" --account-name "$STORAGE" --auth-mode login --output none; then
  echo "    login auth-mode failed, falling back to --auth-mode key"
  az storage container create \
    --name "$CONTAINER" --account-name "$STORAGE" --auth-mode key --output none
fi

echo "==> Azure Cache for Redis: $REDIS"
if az redis show --name "$REDIS" --resource-group "$RG" --output none 2>/dev/null; then
  echo "    already exists, skipping"
  REDIS_CREATED=false
else
  echo "    creating (this can take several minutes)"
  az redis create \
    --name "$REDIS" --resource-group "$RG" --location "$LOCATION" \
    --sku Basic --vm-size c0 --output none
  REDIS_CREATED=true
fi

echo "==> Function App: $FUNCAPP"
if az functionapp show --name "$FUNCAPP" --resource-group "$RG" --output none 2>/dev/null; then
  echo "    already exists, skipping"
  FUNCAPP_CREATED=false
else
  az functionapp create \
    --name "$FUNCAPP" --resource-group "$RG" \
    --consumption-plan-location "$LOCATION" \
    --runtime node --runtime-version 24 --functions-version 4 \
    --storage-account "$STORAGE" --output none
  FUNCAPP_CREATED=true
fi

if [ "$FUNCAPP_CREATED" = true ] && [ "$STORAGE_CREATED" = true ]; then
  echo "==> Wiring CSV storage connection into Function App"
  STORAGE_CONN=$(az storage account show-connection-string \
    --name "$STORAGE" --resource-group "$RG" --query connectionString -o tsv)

  az functionapp config appsettings set \
    --name "$FUNCAPP" --resource-group "$RG" \
    --settings "CSV_STORAGE_CONNECTION=$STORAGE_CONN" --output none
else
  echo "==> Skipping CSV storage connection wiring (Function App and Storage account already existed)"
fi

if [ "$FUNCAPP_CREATED" = true ] && [ "$REDIS_CREATED" = true ]; then
  echo "==> Wiring Redis connection into Function App"
  REDIS_KEY=$(az redis list-keys \
    --name "$REDIS" --resource-group "$RG" --query primaryKey -o tsv)
  REDIS_HOST=$(az redis show \
    --name "$REDIS" --resource-group "$RG" --query hostName -o tsv)

  az functionapp config appsettings set \
    --name "$FUNCAPP" --resource-group "$RG" \
    --settings "REDIS_CONNECTION_STRING=rediss://:$REDIS_KEY@$REDIS_HOST:6380" --output none
else
  echo "==> Skipping Redis connection wiring (Function App and Redis cache already existed)"
fi

echo "==> Static Web App: $SWA (source: $GITHUB_REPO@$GITHUB_BRANCH)"
if az staticwebapp show --name "$SWA" --resource-group "$RG" --output none 2>/dev/null; then
  echo "    already exists, skipping"
  SWA_CREATED=false
else
  echo "    --login-with-github will open a browser auth prompt"
  az staticwebapp create \
    --name "$SWA" --resource-group "$RG" --location "$LOCATION" \
    --source "$GITHUB_REPO" \
    --branch "$GITHUB_BRANCH" \
    --app-location "$APP_LOCATION" \
    --output-location "$OUTPUT_LOCATION" \
    --login-with-github
  SWA_CREATED=true
fi

if [ "$SWA_CREATED" = true ]; then
  echo "==> Linking Function App as Static Web App managed backend"
  FUNCAPP_ID=$(az functionapp show \
    --name "$FUNCAPP" --resource-group "$RG" --query id -o tsv)

  az staticwebapp backends link \
    --name "$SWA" --resource-group "$RG" \
    --backend-resource-id "$FUNCAPP_ID" \
    --backend-region "$LOCATION"
else
  echo "==> Skipping backend link (Static Web App already existed)"
fi

cat <<EOF

==> Done. Provisioned resources:
    Resource group:   $RG
    Storage account:  $STORAGE
    Blob container:   $CONTAINER
    Redis cache:      $REDIS
    Function App:     $FUNCAPP
    Static Web App:   $SWA

    To build and deploy the web-client into this Static Web App, run:
      RG=$RG SWA=$SWA ./release.sh
EOF
