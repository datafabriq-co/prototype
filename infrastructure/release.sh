#!/usr/bin/env bash
#
# Builds web-client and deploys web-client/dist into an already-provisioned
# Static Web App, and builds api and deploys it into the already-provisioned
# Function App (see deploy.sh, which prints the RG/SWA/FUNCAPP to pass here).
#
# Requires: az CLI, already logged in (`az login`) with the target
# subscription selected (`az account set --subscription <id>`).
#
# Usage:
#   RG=rg-prototype-daily-metrics SWA=swa-daily-metrics-abc123 \
#     FUNCAPP=func-daily-metrics-abc123 ./release.sh

set -euo pipefail

# --- variables (override any of these via environment) ---
RG="${RG:-rg-prototype-daily-metrics}"
SUFFIX="${SUFFIX:-be6c8a}"
FUNCAPP="${FUNCAPP:-func-daily-metrics-$SUFFIX}"
SWA="${SWA:-swa-daily-metrics-$SUFFIX}"
APP_LOCATION="${APP_LOCATION:-web-client}"
OUTPUT_LOCATION="${OUTPUT_LOCATION:-dist}"
API_LOCATION="${API_LOCATION:-api}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_CLIENT_DIR="${WEB_CLIENT_DIR:-$SCRIPT_DIR/../$APP_LOCATION}"
API_DIR="${API_DIR:-$SCRIPT_DIR/../$API_LOCATION}"

if ! command -v az >/dev/null 2>&1; then
  echo "Error: az CLI not found. Install the Azure CLI first." >&2
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  echo "Error: not logged in to Azure CLI. Run 'az login' first." >&2
  exit 1
fi

echo "==> Building web-client ($WEB_CLIENT_DIR)"
( cd "$WEB_CLIENT_DIR" && npm ci && npm run build )

echo "==> Deploying $WEB_CLIENT_DIR/$OUTPUT_LOCATION to Static Web App: $SWA"
SWA_DEPLOY_TOKEN=$(az staticwebapp secrets list \
  --name "$SWA" --resource-group "$RG" --query properties.apiKey -o tsv)

npx --yes @azure/static-web-apps-cli deploy \
  "$WEB_CLIENT_DIR/$OUTPUT_LOCATION" \
  --deployment-token "$SWA_DEPLOY_TOKEN" \
  --env production

echo "==> Done. Deployed $WEB_CLIENT_DIR/$OUTPUT_LOCATION to $SWA's production environment."

echo "==> Building api ($API_DIR)"
( cd "$API_DIR" && npm ci && npm run build )

echo "==> Packaging api for deployment"
API_ZIP="$(mktemp -t api-deploy-XXXXXX).zip"
( cd "$API_DIR" && zip -r -q "$API_ZIP" host.json package.json package-lock.json dist )

echo "==> Enabling remote build on Function App: $FUNCAPP"
az functionapp config appsettings set \
  --name "$FUNCAPP" --resource-group "$RG" \
  --settings "SCM_DO_BUILD_DURING_DEPLOYMENT=true" --output none

echo "==> Deploying $API_DIR to Function App: $FUNCAPP"
az functionapp deployment source config-zip \
  --name "$FUNCAPP" --resource-group "$RG" --src "$API_ZIP"

rm -f "$API_ZIP"

echo "==> Done. Deployed $API_DIR to Function App: $FUNCAPP"
