#!/usr/bin/env bash
# ==============================================================================
# scripts/setup.sh
# 
# Preflight checks + terraform init/validate/plan for the root Terraform stack.
# Automatically handles KodeKloud Azure Sandbox session rotations by detecting
# active Azure accounts/subscriptions/resource groups and safely resetting local
# Terraform state when a resource group mismatch is detected.
#
# Does NOT run `terraform apply` - review the plan yourself and apply explicitly:
#   terraform apply tfplan.out
#
# Usage:
#   ./scripts/setup.sh              # Check environment and generate plan
#   ./scripts/setup.sh --reset-state # Safely archive and reset root Terraform state
#   ./scripts/setup.sh --help       # Show this help text
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
PLAN_FILE="${REPO_ROOT}/tfplan.out"

# Immediate help check before running Azure preflights
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo -e "${CYAN}${BOLD}=== KodeKloud Azure Sandbox: Root Stack Setup ===${NC}"
  echo
  echo "Usage: ./scripts/setup.sh [OPTION]"
  echo
  echo "Options:"
  echo "  (no args)       Run preflight checks, sync state, and generate deployment plan"
  echo "  --reset-state   Safely archive and reset local root Terraform state"
  echo "  -h, --help      Display this help message"
  exit 0
fi

echo -e "${CYAN}${BOLD}=== Checking Environment Readiness for Azure Sandbox ===${NC}"
echo

# ------------------------------------------------------------------------------
# 1. Preflight Checks
# ------------------------------------------------------------------------------
if ! command -v az >/dev/null 2>&1; then
  echo -e "${RED}ERROR: Azure CLI ('az') is not installed. Install it and run 'az login'.${NC}" >&2
  exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo -e "${RED}ERROR: Terraform is not installed.${NC}" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo -e "${YELLOW}WARN: kubectl not found. Needed after apply to manage AKS - install it before then.${NC}"
fi

if ! az account show >/dev/null 2>&1; then
  echo -e "${RED}ERROR: Not logged into Azure CLI. Run 'az login' first.${NC}" >&2
  exit 1
fi

AZ_USER=$(az account show --query "user.name" -o tsv 2>/dev/null || echo "")
SUB_NAME=$(az account show --query "name" -o tsv 2>/dev/null || echo "")
SUB_ID=$(az account show --query "id" -o tsv 2>/dev/null || echo "")

if [ -z "$SUB_ID" ]; then
  echo -e "${RED}ERROR: Unable to detect active Azure subscription ID.${NC}" >&2
  exit 1
fi

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

  # If explicit resource_group_name exists in terraform.tfvars, use it
  if grep -qE '^\s*resource_group_name\s*=' terraform.tfvars 2>/dev/null; then
    local tfvar_rg
    tfvar_rg=$(grep -E '^\s*resource_group_name\s*=' terraform.tfvars | head -n 1 | cut -d'=' -f2 | tr -d ' "' | tr -d "'")
    if [ -n "$tfvar_rg" ]; then
      echo "$tfvar_rg"
      return 0
    fi
  fi

  # Query candidate resource groups, excluding Azure internal/system groups
  local candidates
  candidates=$(az group list \
    --query "[?! starts_with(name, 'NetworkWatcherRG') && ! starts_with(name, 'MC_') && ! starts_with(name, 'DefaultResourceGroup-') && ! starts_with(name, 'cloud-shell-storage-')].name" \
    -o tsv 2>/dev/null || true)

  if [ -z "$candidates" ]; then
    echo -e "${RED}ERROR: No resource groups found in subscription '${SUB_NAME}'.${NC}" >&2
    echo -e "${RED}Check your Sandbox status with: az group list -o table${NC}" >&2
    return 1
  fi

  # Look for KodeKloud standard pattern: kml_rg_main-<random-id>
  local kml_candidates
  kml_candidates=$(echo "$candidates" | grep -E '^kml_rg_main-' || true)

  if [ -n "$kml_candidates" ]; then
    local kml_count
    kml_count=$(echo "$kml_candidates" | grep -c . || true)
    if [ "$kml_count" -eq 1 ]; then
      echo "$kml_candidates"
      return 0
    fi

    # Multiple kml_rg_main groups: correlate with user suffix if possible
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

    # Fallback to first kml_rg_main candidate
    echo "$kml_candidates" | head -n 1
    return 0
  fi

  # Fallback for non-kml naming conventions (e.g. ODL-azure-xxx or single sandbox group)
  local candidate_count
  candidate_count=$(echo "$candidates" | grep -c . || true)
  if [ "$candidate_count" -eq 1 ]; then
    echo "$candidates"
    return 0
  fi

  # If multiple unknown candidates exist, choose first and notify
  echo "$candidates" | head -n 1
  return 0
}

CURRENT_RG=$(detect_sandbox_rg)
if [ -z "$CURRENT_RG" ]; then
  echo -e "${RED}ERROR: Failed to detect KodeKloud Sandbox resource group.${NC}" >&2
  exit 1
fi

export TF_VAR_resource_group_name="${CURRENT_RG}"
echo -e "${GREEN}✓ Auto-detected Sandbox Resource Group:${NC} ${CURRENT_RG}"

# ------------------------------------------------------------------------------
# 3. State Analysis & Safe Local Reset Helpers
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

    if [ -z "$rg" ]; then
      rg=$(jq -r '
        ([.outputs.resource_group_name.value] + 
         [.resources[].instances[].attributes.resource_group_name]) 
        | map(select(. != null and . != "")) 
        | first // empty
      ' "$state_path" 2>/dev/null || true)
    fi
  fi

  if [ -z "$rg" ]; then
    rg=$(grep -oE '/resourceGroups/[a-zA-Z0-9_.-]+' "$state_path" 2>/dev/null | grep -v '/resourceGroups/MC_' | head -n 1 | sed 's|/resourceGroups/||' || true)
  fi
  if [ -z "$rg" ]; then
    rg=$(grep -oE '"resource_group_name":\s*"[^"]+"' "$state_path" 2>/dev/null | head -n 1 | cut -d'"' -f4 || true)
  fi

  echo "$rg"
}

extract_state_sub_id() {
  local state_path="$1"
  if [ ! -f "$state_path" ]; then
    return 0
  fi

  local sub=""
  if command -v jq >/dev/null 2>&1; then
    sub=$(jq -r '[.resources[].instances[].attributes.id // empty] | map(select(startswith("/subscriptions/"))) | first // empty' "$state_path" 2>/dev/null | cut -d/ -f3 || true)
  fi
  if [ -z "$sub" ]; then
    sub=$(grep -oE '/subscriptions/[a-f0-9-]+' "$state_path" 2>/dev/null | head -n 1 | cut -d/ -f3 || true)
  fi

  echo "$sub"
}

safe_reset_local_state() {
  local old_rg="${1:-unknown}"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_dir="${BACKUP_BASE_DIR}/backup_${old_rg}_${timestamp}"

  mkdir -p "${backup_dir}"

  # Safely archive active state and state backups
  if [ -f "${STATE_FILE}" ]; then
    mv -f "${STATE_FILE}" "${backup_dir}/"
  fi
  if [ -f "${REPO_ROOT}/terraform.tfstate.backup" ]; then
    mv -f "${REPO_ROOT}/terraform.tfstate.backup" "${backup_dir}/"
  fi

  # Remove local state lock and cached plan files
  rm -f "${REPO_ROOT}/.terraform.tfstate.lock.info"
  rm -f "${PLAN_FILE}" "${REPO_ROOT}"/*.tfplan 2>/dev/null || true

  # Clean local backend state cache inside .terraform (preserves downloaded provider plugins)
  rm -f "${REPO_ROOT}/.terraform/terraform.tfstate"* 2>/dev/null || true

  echo -e "${GREEN}✓ Stale state safely archived to:${NC} ${backup_dir}"
  echo -e "${GREEN}✓ Local Terraform state reset completed.${NC}"

  # Reinitialize Terraform configuration cleanly
  echo -e "${CYAN}Reinitializing Terraform configuration...${NC}"
  if ! terraform init -reconfigure -input=false >/dev/null; then
    echo -e "${RED}ERROR: Failed to reinitialize Terraform.${NC}" >&2
    exit 1
  fi
  echo -e "${GREEN}✓ Terraform reinitialized cleanly.${NC}"
}

verify_and_sync_state() {
  if [ ! -f "${STATE_FILE}" ]; then
    return 0
  fi

  local state_rg
  state_rg=$(extract_state_rg "${STATE_FILE}")
  local state_sub
  state_sub=$(extract_state_sub_id "${STATE_FILE}")

  # Compare resource group and subscription from state against current sandbox
  local mismatch=0
  if [ -n "$state_rg" ] && [ "$state_rg" != "$CURRENT_RG" ]; then
    mismatch=1
  fi
  if [ -n "$state_sub" ] && [ "$state_sub" != "$SUB_ID" ]; then
    mismatch=1
  fi

  if [ "$mismatch" -eq 1 ]; then
    echo
    echo -e "${YELLOW}${BOLD}============================================================${NC}"
    echo -e "${YELLOW}${BOLD}⚠ Sandbox Session Change Detected!${NC}"
    echo -e "${YELLOW}${BOLD}============================================================${NC}"
    echo -e "Previous State Resource Group: ${RED}${state_rg:-unknown}${NC}"
    echo -e "Current Sandbox Resource Group:  ${GREEN}${CURRENT_RG}${NC}"
    if [ -n "$state_sub" ] && [ "$state_sub" != "$SUB_ID" ]; then
      echo -e "Previous State Subscription:   ${RED}${state_sub}${NC}"
      echo -e "Current Active Subscription:   ${GREEN}${SUB_ID}${NC}"
    fi
    echo
    echo -e "${BOLD}Explanation:${NC}"
    echo -e "  The previous KodeKloud Azure Sandbox session has expired."
    echo -e "  Local Terraform state still references resources from the old resource group."
    echo -e "  Refreshing resources across sandbox boundaries triggers Azure '403 Forbidden'"
    echo -e "  (AuthorizationFailed) errors because the old resource group is no longer accessible."
    echo
    echo -e "${CYAN}Resetting local Terraform state to ensure safe deployment in new sandbox...${NC}"
    safe_reset_local_state "${state_rg:-unknown}"
    echo -e "${YELLOW}============================================================${NC}"
    echo
  else
    echo -e "${GREEN}✓ Local Terraform state aligns with current Sandbox resource group.${NC}"
  fi
}

# ------------------------------------------------------------------------------
# 4. Command Handlers
# ------------------------------------------------------------------------------

# Handle --reset-state
if [[ "${1:-}" == "--reset-state" ]]; then
  echo
  if [ -f "${STATE_FILE}" ]; then
    STATE_RG=$(extract_state_rg "${STATE_FILE}")
    echo -e "${CYAN}Manually resetting local root Terraform state...${NC}"
    safe_reset_local_state "${STATE_RG:-manual_reset}"
  else
    echo -e "${YELLOW}No local state file found in root directory. Reinitializing...${NC}"
    terraform init -reconfigure -input=false
  fi
  echo -e "${GREEN}✓ Local Terraform state is clean and ready.${NC}"
  exit 0
fi

# ------------------------------------------------------------------------------
# 5. Execution: Sync, Init, Validate, Plan
# ------------------------------------------------------------------------------
verify_and_sync_state

echo
echo -e "${CYAN}Initializing Terraform...${NC}"
if ! terraform init -input=false; then
  echo -e "${RED}ERROR: Terraform initialization failed.${NC}" >&2
  exit 1
fi

echo -e "${CYAN}Formatting code...${NC}"
terraform fmt -recursive

echo -e "${CYAN}Validating configuration...${NC}"
if ! terraform validate; then
  echo -e "${RED}ERROR: Terraform validation failed.${NC}" >&2
  exit 1
fi

echo -e "${CYAN}Generating plan in ${CURRENT_RG}...${NC}"
if ! terraform plan \
  -var="resource_group_name=${CURRENT_RG}" \
  -var="subscription_id=${SUB_ID}" \
  -out="${PLAN_FILE}"; then
  echo -e "${RED}ERROR: Terraform plan failed.${NC}" >&2
  rm -f "${PLAN_FILE}"
  exit 1
fi

echo
echo -e "${GREEN}${BOLD}✓ Plan complete.${NC} Review it above, then apply with:"
echo "    terraform apply tfplan.out"
