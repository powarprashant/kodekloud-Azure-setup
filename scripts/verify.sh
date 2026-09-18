#!/usr/bin/env bash
# ==============================================================================
# scripts/verify.sh
# 
# Non-destructive status check of deployed infrastructure across all stacks.
# Safe to run at any time - only reads state and queries Azure, never modifies anything.
# Automatically detects active Azure sandbox sessions and flags stale state.
#
# Usage:
#   ./scripts/verify.sh             # Verify infrastructure status
#   ./scripts/verify.sh --help      # Show this help text
# ==============================================================================

set -euo pipefail

RED="\e[0;31m"
GREEN="\e[0;32m"
YELLOW="\e[0;33m"
CYAN="\e[0;36m"
BOLD="\e[1m"
NC="\e[0m"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

pass() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

# Immediate help check before running Azure preflights
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo -e "${CYAN}${BOLD}=== KodeKloud Azure Sandbox: Infrastructure Verification ===${NC}"
  echo
  echo "Usage: ./scripts/verify.sh [OPTION]"
  echo
  echo "Options:"
  echo "  (no args)       Verify active Azure session and deployed infrastructure"
  echo "  -h, --help      Display this help message"
  exit 0
fi

echo -e "${CYAN}${BOLD}=== KodeKloud Azure Sandbox - Infrastructure Verification ===${NC}"
echo

# ------------------------------------------------------------------------------
# 1. Azure Authentication & Active Subscription
# ------------------------------------------------------------------------------
if ! az account show >/dev/null 2>&1; then
  fail "Azure CLI not authenticated. Run: az login"
  exit 1
fi

AZ_USER=$(az account show --query "user.name" -o tsv 2>/dev/null || echo "")
SUB_NAME=$(az account show --query "name" -o tsv 2>/dev/null || echo "")
SUB_ID=$(az account show --query "id" -o tsv 2>/dev/null || echo "")

pass "Azure CLI authenticated as: ${AZ_USER}"
pass "Active Subscription: ${SUB_NAME} (${SUB_ID})"

# ------------------------------------------------------------------------------
# 2. Sandbox Resource Group Auto-Discovery
# ------------------------------------------------------------------------------
detect_sandbox_rg() {
  if [ -n "${TF_VAR_resource_group_name:-}" ]; then
    echo "$TF_VAR_resource_group_name"
    return 0
  fi

  local candidates
  candidates=$(az group list \
    --query "[?! starts_with(name, 'NetworkWatcherRG') && ! starts_with(name, 'MC_') && ! starts_with(name, 'DefaultResourceGroup-') && ! starts_with(name, 'cloud-shell-storage-')].name" \
    -o tsv 2>/dev/null || true)

  local kml_candidates
  kml_candidates=$(echo "$candidates" | grep -E '^kml_rg_main-' || true)

  if [ -n "$kml_candidates" ]; then
    local kml_count
    kml_count=$(echo "$kml_candidates" | grep -c . || true)
    if [ "$kml_count" -eq 1 ]; then
      echo "$kml_candidates"
      return 0
    fi

    if [ -n "$AZ_USER" ]; then
      local user_suffix
      user_suffix=$(echo "$AZ_USER" | grep -oE "main-[a-f0-9]+" || true)
      if [ -n "$user_suffix" ]; then
        local user_match
        user_match=$(echo "$kml_candidates" | grep -F "$user_suffix" | head -n 1 || true)
        if [ -n "$user_match" ]; then
          echo "$user_match"
          return 0
        fi
      fi
    fi

    echo "$kml_candidates" | head -n 1
    return 0
  fi

  local candidate_count
  candidate_count=$(echo "$candidates" | grep -c . || true)
  if [ "$candidate_count" -eq 1 ]; then
    echo "$candidates"
    return 0
  fi

  echo "$candidates" | head -n 1
  return 0
}

CURRENT_RG=$(detect_sandbox_rg)
if [ -n "$CURRENT_RG" ] && az group show --name "$CURRENT_RG" >/dev/null 2>&1; then
  pass "Current Sandbox Resource Group exists: ${CURRENT_RG}"
else
  warn "Could not auto-detect active Sandbox Resource Group."
fi

# ------------------------------------------------------------------------------
# 3. Helper to Check State Alignment
# ------------------------------------------------------------------------------
extract_state_rg() {
  local state_path="$1"
  if [ ! -f "$state_path" ]; then
    return 0
  fi

  local rg=""
  if command -v jq >/dev/null 2>&1; then
    rg=$(jq -r '
      ([.outputs.resource_group_name.value] + 
       [.resources[].instances[].attributes.resource_group_name] + 
       [.resources[].instances[].attributes.name]) 
      | map(select(. != null and . != "" and (startswith("kml_rg_") or startswith("ODL-") or startswith("rg-")))) 
      | first // empty
    ' "$state_path" 2>/dev/null || true)
  fi

  if [ -z "$rg" ]; then
    rg=$(grep -oE '/resourceGroups/[a-zA-Z0-9_.-]+' "$state_path" 2>/dev/null | grep -v '/resourceGroups/MC_' | head -n 1 | sed 's|/resourceGroups/||' || true)
  fi

  echo "$rg"
}

# ------------------------------------------------------------------------------
# 4. Root Stack Verification
# ------------------------------------------------------------------------------
echo
echo -e "${BOLD}--- Root Stack Verification ---${NC}"
ROOT_STATE="${REPO_ROOT}/terraform.tfstate"
if [ -f "$ROOT_STATE" ]; then
  ROOT_STATE_RG=$(extract_state_rg "$ROOT_STATE")
  if [ -n "$ROOT_STATE_RG" ] && [ -n "$CURRENT_RG" ] && [ "$ROOT_STATE_RG" != "$CURRENT_RG" ]; then
    warn "Root state belongs to an expired Sandbox (${ROOT_STATE_RG}). Current active is (${CURRENT_RG})."
  else
    OUTPUTS=$(terraform output -json 2>/dev/null || echo "{}")
    if [ "$OUTPUTS" != "{}" ] && [ -n "$OUTPUTS" ]; then
      RG=$(echo "$OUTPUTS" | jq -r '.resource_group_name.value // empty' 2>/dev/null || true)
      VNET=$(echo "$OUTPUTS" | jq -r '.vnet_name.value // empty' 2>/dev/null || true)
      VM=$(echo "$OUTPUTS" | jq -r '.vm_name.value // empty' 2>/dev/null || true)
      ACR=$(echo "$OUTPUTS" | jq -r '.acr_name.value // empty' 2>/dev/null || true)
      AKS=$(echo "$OUTPUTS" | jq -r '.aks_cluster_name.value // empty' 2>/dev/null || true)

      [ -n "$RG" ] && [ -n "$VNET" ] && az network vnet show --resource-group "$RG" --name "$VNET" >/dev/null 2>&1 && pass "Virtual network: $VNET" || true
      [ -n "$RG" ] && [ -n "$VM" ] && az vm show --resource-group "$RG" --name "$VM" >/dev/null 2>&1 && pass "VM: $VM" || true
      [ -n "$ACR" ] && az acr show --name "$ACR" >/dev/null 2>&1 && pass "ACR: $ACR" || true
      [ -n "$RG" ] && [ -n "$AKS" ] && az aks show --resource-group "$RG" --name "$AKS" >/dev/null 2>&1 && pass "AKS: $AKS" || true
    fi
  fi
else
  echo -e "No root stack deployment found (terraform.tfstate absent)."
fi

# ------------------------------------------------------------------------------
# 5. Ubuntu VM Stack Verification
# ------------------------------------------------------------------------------
echo
echo -e "${BOLD}--- Ubuntu VM Stack Verification ---${NC}"
UBUNTU_STATE="${REPO_ROOT}/ubuntu-vm/terraform.tfstate"
if [ -f "$UBUNTU_STATE" ]; then
  UBUNTU_RG=$(extract_state_rg "$UBUNTU_STATE")
  if [ -n "$UBUNTU_RG" ] && [ -n "$CURRENT_RG" ] && [ "$UBUNTU_RG" != "$CURRENT_RG" ]; then
    warn "Ubuntu VM state is from an expired Sandbox (${UBUNTU_RG}). Run './ubuntu-vm.sh' to re-deploy."
  else
    UBUNTU_VM=$(terraform -chdir="${REPO_ROOT}/ubuntu-vm" output -raw vm_name 2>/dev/null || echo "")
    UBUNTU_IP=$(terraform -chdir="${REPO_ROOT}/ubuntu-vm" output -raw public_ip 2>/dev/null || echo "")
    if [ -n "$UBUNTU_VM" ] && [ -n "$CURRENT_RG" ]; then
      POWER=$(az vm get-instance-view --resource-group "$CURRENT_RG" --name "$UBUNTU_VM" --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus | [0]" -o tsv 2>/dev/null || echo "")
      pass "Ubuntu VM '${UBUNTU_VM}' online at ${UBUNTU_IP} (${POWER:-running})"
    fi
  fi
else
  echo -e "No Ubuntu VM deployment found."
fi

# ------------------------------------------------------------------------------
# 6. Windows VM Stack Verification
# ------------------------------------------------------------------------------
echo
echo -e "${BOLD}--- Windows VM Stack Verification ---${NC}"
WIN_STATE="${REPO_ROOT}/windows-vm/terraform.tfstate"
if [ -f "$WIN_STATE" ]; then
  WIN_RG=$(extract_state_rg "$WIN_STATE")
  if [ -n "$WIN_RG" ] && [ -n "$CURRENT_RG" ] && [ "$WIN_RG" != "$CURRENT_RG" ]; then
    warn "Windows VM state is from an expired Sandbox (${WIN_RG}). Run './windows-vm.sh' to re-deploy."
  else
    WIN_VM=$(terraform -chdir="${REPO_ROOT}/windows-vm" output -raw vm_name 2>/dev/null || echo "")
    WIN_IP=$(terraform -chdir="${REPO_ROOT}/windows-vm" output -raw public_ip 2>/dev/null || echo "")
    if [ -n "$WIN_VM" ] && [ -n "$CURRENT_RG" ]; then
      POWER=$(az vm get-instance-view --resource-group "$CURRENT_RG" --name "$WIN_VM" --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus | [0]" -o tsv 2>/dev/null || echo "")
      pass "Windows VM '${WIN_VM}' online at ${WIN_IP} (${POWER:-running})"
    fi
  fi
else
  echo -e "No Windows VM deployment found."
fi

# ------------------------------------------------------------------------------
# 7. AKS & ACR Stack Verification
# ------------------------------------------------------------------------------
echo
echo -e "${BOLD}--- AKS & ACR Stack Verification ---${NC}"
AKS_STATE="${REPO_ROOT}/aks/terraform.tfstate"
if [ -f "$AKS_STATE" ]; then
  AKS_RG=$(extract_state_rg "$AKS_STATE")
  if [ -n "$AKS_RG" ] && [ -n "$CURRENT_RG" ] && [ "$AKS_RG" != "$CURRENT_RG" ]; then
    warn "AKS state is from an expired Sandbox (${AKS_RG}). Run './aks-setup.sh' to re-deploy."
  else
    AKS_NAME=$(terraform -chdir="${REPO_ROOT}/aks" output -raw aks_cluster_name 2>/dev/null || echo "")
    ACR_NAME=$(terraform -chdir="${REPO_ROOT}/aks" output -raw acr_name 2>/dev/null || echo "")
    if [ -n "$AKS_NAME" ] && [ -n "$CURRENT_RG" ]; then
      STATE=$(az aks show --resource-group "$CURRENT_RG" --name "$AKS_NAME" --query "powerState.code" -o tsv 2>/dev/null || echo "")
      pass "AKS cluster '${AKS_NAME}' exists (${STATE:-running})"
      if command -v kubectl >/dev/null 2>&1; then
        az aks get-credentials --resource-group "$CURRENT_RG" --name "$AKS_NAME" --overwrite-existing >/dev/null 2>&1 || true
        NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")
        READY_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || true)
        pass "kubectl connectivity OK: ${READY_COUNT}/${NODE_COUNT} nodes Ready"
      fi
    fi
    if [ -n "$ACR_NAME" ]; then
      az acr show --name "$ACR_NAME" >/dev/null 2>&1 && pass "ACR registry '${ACR_NAME}' exists" || true
    fi
  fi
else
  echo -e "No AKS & ACR deployment found."
fi

echo
echo -e "${GREEN}${BOLD}Verification check completed.${NC}"
