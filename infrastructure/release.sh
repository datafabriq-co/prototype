#!/usr/bin/env bash
#
# Builds web-client and deploys web-client/dist into an already-provisioned
# Static Web App (see deploy.sh, which prints the RG/SWA to pass here).
#
# Requires: az CLI, already logged in (`az login`) with the target
# subscription selected (`az account set --subscription <id>`).
#
# Usage:
#   RG=rg-daily-metrics-dashboard SWA=swa-daily-metrics-abc123 ./release.sh

set -euo pipefail

RG="${RG:?RG must be set to the resource group printed by deploy.sh}"
SWA="${SWA:?SWA must be set to the Static Web App name printed by deploy.sh}"
APP_LOCATION="${APP_LOCATION:-web-client}"
OUTPUT_LOCATION="${OUTPUT_LOCATION:-dist}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_CLIENT_DIR="${WEB_CLIENT_DIR:-$SCRIPT_DIR/../$APP_LOCATION}"

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
