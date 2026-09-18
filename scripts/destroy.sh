#!/usr/bin/env bash
# ==============================================================================
# scripts/destroy.sh
# 
# Confirmation-gated `terraform destroy` for the root Terraform stack.
# Automatically detects active Azure accounts/subscriptions/resource groups and
# handles expired sandbox sessions safely (preventing 403 Forbidden).
#
# Usage:
#   ./scripts/destroy.sh            # Destroy root infrastructure
#   ./scripts/destroy.sh --help     # Show this help text
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

STATE_FILE="${REPO_ROOT}/terraform.tfstate"
BACKUP_BASE_DIR="${REPO_ROOT}/.state_backups"

# Immediate help check before running Azure preflights
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo -e "${CYAN}${BOLD}=== KodeKloud Azure Sandbox: Root Stack Teardown ===${NC}"
  echo
  echo "Usage: ./scripts/destroy.sh [OPTION]"
  echo
  echo "Options:"
  echo "  (no args)       Tear down all root-managed Azure infrastructure"
  echo "  -h, --help      Display this help message"
  exit 0
fi

echo -e "${CYAN}${BOLD}=== KodeKloud Azure Sandbox: Root Stack Teardown ===${NC}"
echo

# ------------------------------------------------------------------------------
# 1. Preflight Checks
# ------------------------------------------------------------------------------
if ! command -v az >/dev/null 2>&1; then
  echo -e "${RED}ERROR: Azure CLI ('az') is not installed.${NC}" >&2
  exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo -e "${RED}ERROR: Terraform is not installed.${NC}" >&2
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  echo -e "${RED}ERROR: Not logged into Azure CLI. Run 'az login' first.${NC}" >&2
  exit 1
fi

AZ_USER=$(az account show --query "user.name" -o tsv 2>/dev/null || echo "")
SUB_NAME=$(az account show --query "name" -o tsv 2>/dev/null || echo "")
SUB_ID=$(az account show --query "id" -o tsv 2>/dev/null || echo "")

echo -e "${GREEN}✓ Authenticated as:${NC} ${AZ_USER}"
echo -e "${GREEN}✓ Active Subscription:${NC} ${SUB_NAME} (${SUB_ID})"

# Export environment variables for Terraform azurerm provider
export ARM_SUBSCRIPTION_ID="${SUB_ID}"
export TF_VAR_subscription_id="${SUB_ID}"

# ------------------------------------------------------------------------------
# 2. Dynamic Sandbox Resource Group Detection
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
export TF_VAR_resource_group_name="${CURRENT_RG}"

# ------------------------------------------------------------------------------
# 3. State Analysis
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
  if [ -z "$rg" ]; then
    rg=$(grep -oE '"resource_group_name":\s*"[^"]+"' "$state_path" 2>/dev/null | head -n 1 | cut -d'"' -f4 || true)
  fi

  echo "$rg"
}

if [ ! -f "${STATE_FILE}" ]; then
  echo -e "${YELLOW}No terraform.tfstate found in root directory - nothing to destroy.${NC}"
  exit 0
fi

STATE_RG=$(extract_state_rg "${STATE_FILE}")

# Handle expired sandbox session mismatch
if [ -n "$STATE_RG" ] && [ -n "$CURRENT_RG" ] && [ "$STATE_RG" != "$CURRENT_RG" ]; then
  echo -e "${YELLOW}${BOLD}⚠ WARNING: Stale Sandbox State Detected during destroy${NC}"
  echo -e "Deployment state belongs to an expired Sandbox session (${RED}${STATE_RG}${NC})."
  echo -e "Current active Sandbox is (${GREEN}${CURRENT_RG}${NC})."
  echo -e "Resources in the previous sandbox have already been terminated by KodeKloud."
  echo -e "Attempting to destroy old resources via Azure API will result in 403 Forbidden errors."
  echo
  read -r -p "Do you want to safely archive and clear the stale local root Terraform state? (y/N): " CONFIRM_CLEAN
  if [[ "$CONFIRM_CLEAN" =~ ^[Yy]$ ]]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_DIR="${BACKUP_BASE_DIR}/backup_${STATE_RG}_${TIMESTAMP}"
    mkdir -p "${BACKUP_DIR}"
    mv -f "${STATE_FILE}" "${BACKUP_DIR}/"
    if [ -f "${REPO_ROOT}/terraform.tfstate.backup" ]; then
      mv -f "${REPO_ROOT}/terraform.tfstate.backup" "${BACKUP_DIR}/"
    fi
    rm -f "${REPO_ROOT}/tfplan.out" "${REPO_ROOT}"/*.tfplan 2>/dev/null || true
    echo -e "${GREEN}✓ Stale local state safely archived to: ${BACKUP_DIR}${NC}"
    echo -e "${GREEN}✓ Local root Terraform state is clean.${NC}"
  fi
  exit 0
fi

echo -e "${YELLOW}This will destroy every resource managed by this Terraform state in ${CURRENT_RG}:${NC}"
terraform state list 2>/dev/null || { echo -e "${RED}No terraform state found - nothing to destroy.${NC}"; exit 0; }

echo
read -r -p "Type 'destroy' to confirm: " CONFIRM
if [ "$CONFIRM" != "destroy" ]; then
  echo "Aborted. No changes made."
  exit 1
fi

echo -e "${CYAN}Destroying infrastructure...${NC}"
if ! terraform destroy -auto-approve \
  -var="resource_group_name=${CURRENT_RG}" \
  -var="subscription_id=${SUB_ID}"; then
  echo -e "${RED}ERROR: Terraform destroy failed.${NC}" >&2
  exit 1
fi

echo
rm -f tfplan.out *_key.pem *_credentials.txt *.rdp 2>/dev/null || true
echo -e "${GREEN}✓ Infrastructure destroyed successfully.${NC}"
