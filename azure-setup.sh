#!/usr/bin/env bash
# ============================================================================
# One-time Azure setup for the Splinter site on Azure Container Apps.
#
# Run this AFTER the first GitHub Actions build has pushed an image to GHCR
# and you've made the package public (see README "Deploying" section).
#
# Prereqs: az CLI (https://learn.microsoft.com/cli/azure/install-azure-cli)
#          gh CLI, authenticated as the repo owner
# Cost:    Container Apps consumption plan — the free monthly grant
#          (180k vCPU-s, 360k GiB-s, 2M requests) covers a low-traffic site
#          that scales to zero. No Azure Container Registry involved (GHCR is
#          free) — nothing here has a standing monthly charge.
# ============================================================================
set -euo pipefail

RG="splinter-rg"
LOCATION="uksouth"
ENV_NAME="splinter-env"
APP_NAME="splinter-web"
REPO="xpenno255/splinter-website"
IMAGE="ghcr.io/${REPO}:latest"

echo "==> Logging in (browser window will open)"
az login

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "    Subscription: ${SUBSCRIPTION_ID}"

echo "==> Registering resource providers (idempotent, may take a minute)"
az provider register --namespace Microsoft.App --wait
az provider register --namespace Microsoft.OperationalInsights --wait

echo "==> Resource group"
az group create --name "$RG" --location "$LOCATION" -o none

echo "==> Container Apps environment"
az containerapp env create \
  --name "$ENV_NAME" --resource-group "$RG" --location "$LOCATION" -o none

echo "==> Container App (scale-to-zero, public ingress on port 80)"
az containerapp create \
  --name "$APP_NAME" --resource-group "$RG" --environment "$ENV_NAME" \
  --image "$IMAGE" \
  --target-port 80 --ingress external \
  --min-replicas 0 --max-replicas 1 \
  --cpu 0.25 --memory 0.5Gi -o none

FQDN=$(az containerapp show -n "$APP_NAME" -g "$RG" \
  --query properties.configuration.ingress.fqdn -o tsv)

echo "==> App registration for GitHub Actions OIDC deploys"
APP_ID=$(az ad app create --display-name splinter-deploy --query appId -o tsv)
az ad sp create --id "$APP_ID" -o none 2>/dev/null || true

az ad app federated-credential create --id "$APP_ID" --parameters "{
  \"name\": \"github-main\",
  \"issuer\": \"https://token.actions.githubusercontent.com\",
  \"subject\": \"repo:${REPO}:ref:refs/heads/main\",
  \"audiences\": [\"api://AzureADTokenExchange\"]
}" -o none

echo "==> Granting the app Contributor on the resource group"
az role assignment create \
  --assignee "$APP_ID" \
  --role Contributor \
  --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG}" -o none

echo "==> Storing deploy credentials as GitHub repo secrets"
gh secret set AZURE_CLIENT_ID       --repo "$REPO" --body "$APP_ID"
gh secret set AZURE_TENANT_ID       --repo "$REPO" --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --repo "$REPO" --body "$SUBSCRIPTION_ID"
gh variable set AZURE_CONFIGURED    --repo "$REPO" --body "true"

echo ""
echo "============================================================"
echo "  Done. Site: https://${FQDN}"
echo "  Every push to main now builds + deploys automatically."
echo "============================================================"
