#!/usr/bin/env bash
# Preflight checks + terraform init/fmt/validate/plan for the
# KodeKloud Azure Sandbox lab. Does NOT run `terraform apply` -
# review the plan yourself and apply it explicitly.
#
#   ./scripts/setup.sh
set -uo pipefail

RED="\e[0;31m"
GREEN="\e[0;32m"
YELLOW="\e[0;33m"
NC="\e[0m"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "Checking environment readiness to deploy..."

err=0

if ! command -v az >/dev/null 2>&1; then
  echo -e "${RED}Azure CLI (az) is not installed. Install it, then run: az login${NC}"
  err=1
else
  echo -e "${GREEN}- az cli found: $(az version --query '"azure-cli"' -o tsv 2>/dev/null)${NC}"
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo -e "${RED}terraform is not installed.${NC}"
  err=1
else
  echo -e "${GREEN}- terraform found: $(terraform version -json 2>/dev/null | grep -oE '"terraform_version"\s*:\s*"[^"]*"' | cut -d'"' -f4)${NC}"
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo -e "${YELLOW}WARN: kubectl not found. Needed after apply to talk to AKS - install it before then.${NC}"
fi

if [ "$err" -eq 1 ]; then
  echo -e "${RED}Fix the above and re-run.${NC}"
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  echo -e "${RED}Not logged in to Azure CLI. Run: az login${NC}"
  exit 1
fi

SUB_NAME=$(az account show --query name -o tsv)
SUB_ID=$(az account show --query id -o tsv)
echo -e "${GREEN}- Logged in. Active subscription: ${SUB_NAME} (${SUB_ID})${NC}"

# Auto-detect the sandbox's pre-provisioned resource group, unless the
# user already set one via env var or terraform.tfvars. The azurerm
# provider has no "list resource groups" data source, so this lives here
# rather than in Terraform itself (see modules/resource-group/main.tf).
if [ -z "${TF_VAR_resource_group_name:-}" ] && ! grep -qE '^\s*resource_group_name\s*=' terraform.tfvars 2>/dev/null; then
  CANDIDATES=$(az group list \
    --query "[?! starts_with(name, 'NetworkWatcherRG') && ! starts_with(name, 'MC_') && ! starts_with(name, 'DefaultResourceGroup-') && ! starts_with(name, 'cloud-shell-storage-')].name" \
    -o tsv 2>/dev/null)
  CANDIDATE_COUNT=$(echo "$CANDIDATES" | grep -c . || true)

  if [ "$CANDIDATE_COUNT" -eq 1 ]; then
    export TF_VAR_resource_group_name="$CANDIDATES"
    echo -e "${GREEN}- Auto-detected resource group: ${TF_VAR_resource_group_name}${NC}"
  elif [ "$CANDIDATE_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}WARN: No resource group found. If this is the KodeKloud Sandbox, one should already exist - double check with: az group list -o table${NC}"
  else
    echo -e "${YELLOW}WARN: Multiple candidate resource groups found - can't auto-detect. Set resource_group_name in terraform.tfvars:${NC}"
    echo "$CANDIDATES" | sed 's/^/    /'
  fi
fi

echo
echo "Running terraform init / fmt / validate / plan..."
terraform init -input=false || exit 1
terraform fmt -recursive
terraform validate || exit 1
terraform plan -out=tfplan.out

echo
echo -e "${GREEN}Plan complete.${NC} Review it above, then apply with:"
echo "    terraform apply tfplan.out"
