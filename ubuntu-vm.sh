#!/usr/bin/env bash
# ==============================================================================
# ubuntu-vm.sh
# 
# One-shot provisioning of an Ubuntu 22.04 LTS VM with Docker, Docker Compose,
# and DevOps tools pre-installed. Designed specifically for KodeKloud Azure Sandbox.
#
# Automatically handles Sandbox session rotations by detecting active Azure
# accounts/subscriptions/resource groups and safely resetting local Terraform
# state when a resource group mismatch is detected (preventing 403 Forbidden).
#
# Usage:
#   ./ubuntu-vm.sh              # Provision Ubuntu VM (auto-detects & resets stale state)
#   ./ubuntu-vm.sh --plan       # Plan deployment without applying
#   ./ubuntu-vm.sh --reset-state# Safely reset local Terraform state
#   ./ubuntu-vm.sh --ssh        # SSH directly into the VM
#   ./ubuntu-vm.sh --status     # Check VM power state and IP
#   ./ubuntu-vm.sh --destroy    # Tear down Ubuntu VM only
#   ./ubuntu-vm.sh --help       # Show this help text
# ==============================================================================

set -euo pipefail

# ANSI color codes
RED="\e[0;31m"
GREEN="\e[0;32m"
YELLOW="\e[0;33m"
CYAN="\e[0;36m"
BOLD="\e[1m"
NC="\e[0m"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="${REPO_ROOT}/ubuntu-vm"
STATE_FILE="${STACK_DIR}/terraform.tfstate"
BACKUP_BASE_DIR="${STACK_DIR}/.state_backups"
PLAN_FILE="${STACK_DIR}/tfplan.out"

# Immediate help check before running Azure preflights
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo -e "${CYAN}${BOLD}=== KodeKloud Azure Sandbox: Ubuntu VM Setup ===${NC}"
  echo
  echo "Usage: ./ubuntu-vm.sh [OPTION]"
  echo
  echo "Options:"
  echo "  (no args)       Provision or update the Ubuntu VM (auto-detects RG & resets stale state)"
  echo "  --plan          Plan the deployment without applying changes"
  echo "  --reset-state   Safely archive and reset local Terraform state"
  echo "  --status        Check current VM power state, provisioning status, and IP"
  echo "  --ssh           SSH directly into the VM using the generated private key"
  echo "  --destroy       Tear down the Ubuntu VM infrastructure"
  echo "  -h, --help      Display this help message"
  exit 0
fi

echo -e "${CYAN}${BOLD}=== KodeKloud Azure Sandbox: Ubuntu VM Setup ===${NC}"
echo

# ------------------------------------------------------------------------------
# 1. Preflight checks
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

# Detect authenticated account & subscription
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
    rg=$(grep -oE '/resourceGroups/[a-zA-Z0-9_.-]+' "$state_path" 2>/dev/null | head -n 1 | sed 's|/resourceGroups/||' || true)
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
  if [ -f "${STACK_DIR}/terraform.tfstate" ]; then
    mv -f "${STACK_DIR}/terraform.tfstate" "${backup_dir}/"
  fi
  if [ -f "${STACK_DIR}/terraform.tfstate.backup" ]; then
    mv -f "${STACK_DIR}/terraform.tfstate.backup" "${backup_dir}/"
  fi

  # Remove local state lock and cached plan files
  rm -f "${STACK_DIR}/.terraform.tfstate.lock.info"
  rm -f "${STACK_DIR}/tfplan.out" "${STACK_DIR}"/*.tfplan 2>/dev/null || true

  # Clean local backend state cache inside .terraform (preserves downloaded provider plugins)
  rm -f "${STACK_DIR}/.terraform/terraform.tfstate"* 2>/dev/null || true

  # Archive stale private keys from previous sandbox session to avoid mismatch
  if [ -f "${STACK_DIR}/vm-ubuntu_key.pem" ]; then
    mv -f "${STACK_DIR}/vm-ubuntu_key.pem" "${backup_dir}/"
  fi
  if [ -f "${REPO_ROOT}/vm-ubuntu_key.pem" ]; then
    cp -f "${REPO_ROOT}/vm-ubuntu_key.pem" "${backup_dir}/" 2>/dev/null || true
    rm -f "${REPO_ROOT}/vm-ubuntu_key.pem"
  fi

  echo -e "${GREEN}✓ Stale state and keys safely archived to:${NC} ${backup_dir}"
  echo -e "${GREEN}✓ Local Terraform state reset completed.${NC}"

  # Reinitialize Terraform configuration cleanly
  echo -e "${CYAN}Reinitializing Terraform configuration...${NC}"
  if ! terraform -chdir="${STACK_DIR}" init -reconfigure -input=false >/dev/null; then
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
    echo -e "${CYAN}Manually resetting local Terraform state...${NC}"
    safe_reset_local_state "${STATE_RG:-manual_reset}"
  else
    echo -e "${YELLOW}No local state file found in ubuntu-vm/. Reinitializing...${NC}"
    terraform -chdir="${STACK_DIR}" init -reconfigure -input=false
  fi
  echo -e "${GREEN}✓ Local Terraform state is clean and ready.${NC}"
  exit 0
fi

# Handle --destroy
if [[ "${1:-}" == "--destroy" ]]; then
  echo
  if [ ! -f "${STATE_FILE}" ]; then
    echo -e "${YELLOW}No deployment state found in ubuntu-vm/. Nothing to destroy.${NC}"
    exit 0
  fi

  STATE_RG=$(extract_state_rg "${STATE_FILE}")
  if [ -n "$STATE_RG" ] && [ "$STATE_RG" != "$CURRENT_RG" ]; then
    echo -e "${YELLOW}${BOLD}⚠ WARNING: Stale Sandbox State Detected during --destroy${NC}"
    echo -e "Deployment state belongs to an expired Sandbox session (${RED}${STATE_RG}${NC})."
    echo -e "Current active Sandbox is (${GREEN}${CURRENT_RG}${NC})."
    echo -e "Resources in the previous sandbox have already been terminated by KodeKloud."
    echo -e "Attempting to destroy old resources via Azure API will result in 403 Forbidden errors."
    echo
    read -r -p "Do you want to safely clear the stale local Terraform state? (y/N): " CONFIRM_CLEAN
    if [[ "$CONFIRM_CLEAN" =~ ^[Yy]$ ]]; then
      safe_reset_local_state "${STATE_RG}"
      echo -e "${GREEN}✓ Stale local state cleaned successfully.${NC}"
    fi
    exit 0
  fi

  echo -e "${YELLOW}WARNING: This will destroy the Ubuntu VM, Public IP, NIC, NSG, Subnet, and VNet.${NC}"
  read -r -p "Type 'destroy' to confirm: " CONFIRM
  if [ "$CONFIRM" != "destroy" ]; then
    echo "Aborted."
    exit 1
  fi

  echo -e "${CYAN}Destroying Ubuntu VM resources in ${CURRENT_RG}...${NC}"
  if ! terraform -chdir="${STACK_DIR}" destroy -auto-approve \
    -var="resource_group_name=${CURRENT_RG}" \
    -var="subscription_id=${SUB_ID}"; then
    echo -e "${RED}ERROR: Terraform destroy encountered errors.${NC}" >&2
    exit 1
  fi

  rm -f "${REPO_ROOT}/vm-ubuntu_key.pem" "${STACK_DIR}/vm-ubuntu_key.pem" ~/.ssh/vm-ubuntu_key.pem 2>/dev/null || true
  echo -e "${GREEN}✓ Ubuntu VM destroyed successfully.${NC}"
  exit 0
fi

# Handle --ssh
if [[ "${1:-}" == "--ssh" ]]; then
  if [ ! -f "${STATE_FILE}" ]; then
    echo -e "${RED}ERROR: No deployed VM state found. Run './ubuntu-vm.sh' to provision first.${NC}" >&2
    exit 1
  fi

  STATE_RG=$(extract_state_rg "${STATE_FILE}")
  if [ -n "$STATE_RG" ] && [ "$STATE_RG" != "$CURRENT_RG" ]; then
    echo -e "${RED}ERROR: Deployment state is from an expired Sandbox (${STATE_RG}).${NC}" >&2
    echo -e "Current active Sandbox is (${CURRENT_RG}). Run './ubuntu-vm.sh' to deploy in the active sandbox." >&2
    exit 1
  fi

  PUBLIC_IP=$(terraform -chdir="${STACK_DIR}" output -raw public_ip 2>/dev/null || echo "")
  KEY_FILE="${STACK_DIR}/vm-ubuntu_key.pem"
  if [ ! -f "$KEY_FILE" ]; then
    KEY_FILE="${REPO_ROOT}/vm-ubuntu_key.pem"
  fi

  if [ -z "$PUBLIC_IP" ] || [ ! -f "$KEY_FILE" ]; then
    echo -e "${RED}ERROR: VM IP or private key not found.${NC}" >&2
    exit 1
  fi

  mkdir -p ~/.ssh
  cp -f "$KEY_FILE" ~/.ssh/vm-ubuntu_key.pem
  chmod 600 ~/.ssh/vm-ubuntu_key.pem
  echo -e "${CYAN}Connecting to azureuser@${PUBLIC_IP}...${NC}"
  ssh -i ~/.ssh/vm-ubuntu_key.pem -o StrictHostKeyChecking=no "azureuser@${PUBLIC_IP}"
  exit 0
fi

# Handle --status
if [[ "${1:-}" == "--status" ]]; then
  echo
  echo "Checking Ubuntu VM status..."
  if [ ! -f "${STATE_FILE}" ]; then
    echo -e "${YELLOW}No deployment state found in ubuntu-vm/ directory. Run './ubuntu-vm.sh' to deploy.${NC}"
    exit 0
  fi

  STATE_RG=$(extract_state_rg "${STATE_FILE}")
  if [ -n "$STATE_RG" ] && [ "$STATE_RG" != "$CURRENT_RG" ]; then
    echo -e "${YELLOW}WARNING: Deployment state belongs to an old Sandbox resource group (${STATE_RG}).${NC}"
    echo -e "${YELLOW}Active Sandbox resource group is (${CURRENT_RG}).${NC}"
    echo -e "Run './ubuntu-vm.sh' to deploy in the active sandbox."
    exit 0
  fi

  VM_NAME=$(terraform -chdir="${STACK_DIR}" output -raw vm_name 2>/dev/null || echo "")
  RG_NAME=$(terraform -chdir="${STACK_DIR}" output -raw resource_group_name 2>/dev/null || echo "")
  PUBLIC_IP=$(terraform -chdir="${STACK_DIR}" output -raw public_ip 2>/dev/null || echo "")

  if [ -n "$VM_NAME" ]; then
    echo -e "${GREEN}✓ VM Name:${NC}    ${VM_NAME}"
    echo -e "${GREEN}✓ Public IP:${NC}  ${PUBLIC_IP}"
    echo -e "${GREEN}✓ Resource Group:${NC} ${RG_NAME}"
    az vm get-instance-view --resource-group "$RG_NAME" --name "$VM_NAME" \
      --query "{PowerState:instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus | [0], Provisioning:instanceView.statuses[?starts_with(code, 'ProvisioningState/')].displayStatus | [0]}" \
      -o table 2>/dev/null || true
  else
    echo -e "${YELLOW}No VM information available in Terraform outputs.${NC}"
  fi
  exit 0
fi

# ------------------------------------------------------------------------------
# 5. Provision / Plan Ubuntu VM
# ------------------------------------------------------------------------------

# Verify local state alignment before init/plan/apply
verify_and_sync_state

# Ensure Terraform is initialized
echo -e "${CYAN}Initializing Terraform in ubuntu-vm/...${NC}"
if ! terraform -chdir="${STACK_DIR}" init -input=false; then
  echo -e "${RED}ERROR: Terraform init failed.${NC}" >&2
  exit 1
fi

# Handle --plan flag
if [[ "${1:-}" == "--plan" ]]; then
  echo
  echo -e "${CYAN}Generating Terraform plan for Ubuntu VM...${NC}"
  if ! terraform -chdir="${STACK_DIR}" plan \
    -var="resource_group_name=${CURRENT_RG}" \
    -var="subscription_id=${SUB_ID}"; then
    echo -e "${RED}ERROR: Terraform plan failed.${NC}" >&2
    exit 1
  fi
  echo -e "${GREEN}✓ Terraform plan succeeded.${NC}"
  exit 0
fi

# Execute Plan to Outfile
echo
echo -e "${CYAN}Planning Ubuntu VM infrastructure in ${CURRENT_RG}...${NC}"
if ! terraform -chdir="${STACK_DIR}" plan \
  -var="resource_group_name=${CURRENT_RG}" \
  -var="subscription_id=${SUB_ID}" \
  -out="${PLAN_FILE}"; then
  echo -e "${RED}ERROR: Terraform plan failed. Aborting deployment.${NC}" >&2
  rm -f "${PLAN_FILE}"
  exit 1
fi

# Execute Apply
echo
echo -e "${CYAN}Applying Ubuntu VM infrastructure (takes ~1-2 minutes)...${NC}"
if ! terraform -chdir="${STACK_DIR}" apply -auto-approve "${PLAN_FILE}"; then
  echo -e "${RED}ERROR: Terraform apply failed. Infrastructure was not fully provisioned.${NC}" >&2
  rm -f "${PLAN_FILE}"
  exit 1
fi
rm -f "${PLAN_FILE}"

# ------------------------------------------------------------------------------
# 6. Post-deployment Setup & Validation
# ------------------------------------------------------------------------------
RG_NAME=$(terraform -chdir="${STACK_DIR}" output -raw resource_group_name 2>/dev/null || echo "")
VM_NAME=$(terraform -chdir="${STACK_DIR}" output -raw vm_name 2>/dev/null || echo "")
PUBLIC_IP=$(terraform -chdir="${STACK_DIR}" output -raw public_ip 2>/dev/null || echo "")

if [ -z "$RG_NAME" ] || [ -z "$VM_NAME" ] || [ -z "$PUBLIC_IP" ]; then
  echo -e "${RED}ERROR: Deployment applied but required Terraform outputs could not be retrieved.${NC}" >&2
  exit 1
fi

KEY_FILE="${STACK_DIR}/${VM_NAME}_key.pem"

# Copy private key to ~/.ssh with strict 0600 permissions (guaranteed to work across WSL mounts and Linux)
mkdir -p ~/.ssh && chmod 700 ~/.ssh
if [ -f "$KEY_FILE" ]; then
  cp -f "$KEY_FILE" ~/.ssh/${VM_NAME}_key.pem
  chmod 600 ~/.ssh/${VM_NAME}_key.pem
  cp -f "$KEY_FILE" "${REPO_ROOT}/${VM_NAME}_key.pem"
  chmod 600 "${REPO_ROOT}/${VM_NAME}_key.pem" 2>/dev/null || true
  chmod 600 "$KEY_FILE" 2>/dev/null || true
fi

echo
echo -e "${GREEN}${BOLD}✓ Ubuntu VM Deployed Successfully!${NC}"
echo
echo -e "${BOLD}==================== DEPLOYMENT SUMMARY ====================${NC}"
echo -e "${BOLD}Resource Group:${NC}      ${RG_NAME}"
echo -e "${BOLD}VM Name:${NC}             ${VM_NAME}"
echo -e "${BOLD}VM Size:${NC}             Standard_B2s (2 vCPU, 4GB RAM)"
echo -e "${BOLD}Public IP:${NC}           ${PUBLIC_IP}"
echo -e "${BOLD}Inbound Security:${NC}    All Traffic Allowed (0.0.0.0/0 - Any Port/Protocol)"
echo -e "${BOLD}SSH User:${NC}            azureuser"
echo -e "${BOLD}Private Key:${NC}         ~/.ssh/${VM_NAME}_key.pem"
echo
echo -e "${CYAN}${BOLD}Pre-installed & Configured Tools:${NC}"
echo -e "  - Docker Engine & Docker Compose v2 (systemd enabled)"
echo -e "  - User 'azureuser' added to 'docker' group (no sudo required)"
echo -e "  - Sysctl tuned for SonarQube & containers (vm.max_map_count=524288)"
echo -e "  - Azure CLI ('az') and Kubernetes CLI ('kubectl')"
echo -e "  - Git, Curl, Wget, JQ, Unzip, Build-Essential"
echo
echo -e "${BOLD}Quick Connect:${NC}"
echo -e "  Direct SSH script: ./ubuntu-vm.sh --ssh"
echo -e "  Manual SSH:        ssh -i ~/.ssh/${VM_NAME}_key.pem azureuser@${PUBLIC_IP}"
echo -e "  Check Status:      ./ubuntu-vm.sh --status"
echo -e "  Destroy VM:        ./ubuntu-vm.sh --destroy"
echo -e "${BOLD}============================================================${NC}"
