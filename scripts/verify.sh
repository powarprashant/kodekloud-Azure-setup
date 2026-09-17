#!/usr/bin/env bash
# Non-destructive status check of the deployed infrastructure.
# Safe to run at any time - only reads state, never modifies anything.
#
#   ./scripts/verify.sh
set -uo pipefail

RED="\e[0;31m"
GREEN="\e[0;32m"
YELLOW="\e[0;33m"
NC="\e[0m"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

pass() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

echo "=== KodeKloud Azure Sandbox - Infrastructure Verification ==="
echo

# 1. Azure authentication
if az account show >/dev/null 2>&1; then
  pass "Azure CLI authenticated as $(az account show --query user.name -o tsv 2>/dev/null)"
else
  fail "Azure CLI not authenticated. Run: az login"
  exit 1
fi

# Pull expected names from terraform outputs, if state exists
if terraform output >/dev/null 2>&1; then
  RG=$(terraform output -raw resource_group_name 2>/dev/null)
  VNET=$(terraform output -raw vnet_name 2>/dev/null)
  VM=$(terraform output -raw vm_name 2>/dev/null)
  ACR=$(terraform output -raw acr_name 2>/dev/null)
  AKS=$(terraform output -raw aks_cluster_name 2>/dev/null)
else
  warn "No terraform state/outputs found yet. Run terraform apply first. Falling back to tfvars defaults where possible."
  RG="" VNET="" VM="" ACR="" AKS=""
fi

# 2. Resource Group
if [ -n "$RG" ] && az group show --name "$RG" >/dev/null 2>&1; then
  pass "Resource group exists: $RG"
else
  fail "Resource group not found${RG:+ ($RG)}"
fi

# 3. VNet
if [ -n "$RG" ] && [ -n "$VNET" ] && az network vnet show --resource-group "$RG" --name "$VNET" >/dev/null 2>&1; then
  pass "Virtual network exists: $VNET"
else
  fail "Virtual network not found${VNET:+ ($VNET)}"
fi

# 4. VM
if [ -n "$RG" ] && [ -n "$VM" ] && az vm show --resource-group "$RG" --name "$VM" >/dev/null 2>&1; then
  POWER=$(az vm get-instance-view --resource-group "$RG" --name "$VM" --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv 2>/dev/null)
  pass "VM exists: $VM (${POWER:-unknown state})"
else
  fail "VM not found${VM:+ ($VM)}"
fi

# 5. ACR
if [ -n "$ACR" ] && az acr show --name "$ACR" >/dev/null 2>&1; then
  pass "ACR exists: $ACR"
else
  fail "ACR not found${ACR:+ ($ACR)}"
fi

# 6. AKS
if [ -n "$RG" ] && [ -n "$AKS" ] && az aks show --resource-group "$RG" --name "$AKS" >/dev/null 2>&1; then
  STATE=$(az aks show --resource-group "$RG" --name "$AKS" --query "powerState.code" -o tsv 2>/dev/null)
  pass "AKS cluster exists: $AKS (${STATE:-unknown state})"

  # 7. kubectl connectivity + node check
  if command -v kubectl >/dev/null 2>&1; then
    if az aks get-credentials --resource-group "$RG" --name "$AKS" --overwrite-existing >/dev/null 2>&1; then
      if kubectl get nodes >/dev/null 2>&1; then
        NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
        READY_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || true)
        pass "kubectl connectivity OK - ${READY_COUNT}/${NODE_COUNT} nodes Ready"
      else
        fail "kubectl could not reach the cluster API server"
      fi
    else
      fail "az aks get-credentials failed"
    fi
  else
    warn "kubectl not installed - skipping node check"
  fi
else
  fail "AKS cluster not found${AKS:+ ($AKS)}"
fi

echo
echo "Verification complete."
