#!/usr/bin/env bash
# ==============================================================================
# windows-vm.sh
# 
# One-shot provisioning of a Windows Server 2022 Datacenter VM with RDP and
# OpenSSH enabled. Designed specifically for KodeKloud Azure Sandbox.
#
# Usage:
#   ./windows-vm.sh            # Provision Windows VM
#   ./windows-vm.sh --status   # Check VM power state and IP
#   ./windows-vm.sh --destroy  # Tear down Windows VM only
# ==============================================================================

set -uo pipefail

RED="\e[0;31m"
GREEN="\e[0;32m"
YELLOW="\e[0;33m"
CYAN="\e[0;36m"
BOLD="\e[1m"
NC="\e[0m"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="${REPO_ROOT}/windows-vm"

echo -e "${CYAN}${BOLD}=== KodeKloud Azure Sandbox: Windows Server 2022 VM Setup ===${NC}"
echo

# 1. Preflight checks
if ! command -v az >/dev/null 2>&1; then
  echo -e "${RED}ERROR: Azure CLI ('az') is not installed.${NC}"
  exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo -e "${RED}ERROR: Terraform is not installed.${NC}"
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  echo -e "${RED}ERROR: Not logged into Azure CLI. Run 'az login' first.${NC}"
  exit 1
fi

SUB_NAME=$(az account show --query name -o tsv)
SUB_ID=$(az account show --query id -o tsv)
echo -e "${GREEN}✓ Authenticated as:${NC} $(az account show --query user.name -o tsv)"
echo -e "${GREEN}✓ Active Subscription:${NC} ${SUB_NAME} (${SUB_ID})"

# 2. Auto-detect KodeKloud Sandbox Resource Group
if [ -z "${TF_VAR_resource_group_name:-}" ]; then
  CANDIDATES=$(az group list \
    --query "[?! starts_with(name, 'NetworkWatcherRG') && ! starts_with(name, 'MC_') && ! starts_with(name, 'DefaultResourceGroup-') && ! starts_with(name, 'cloud-shell-storage-')].name" \
    -o tsv 2>/dev/null)
  CANDIDATE_COUNT=$(echo "$CANDIDATES" | grep -c . || true)

  if [ "$CANDIDATE_COUNT" -eq 1 ]; then
    export TF_VAR_resource_group_name="$CANDIDATES"
    echo -e "${GREEN}✓ Auto-detected Sandbox Resource Group:${NC} ${TF_VAR_resource_group_name}"
  elif [ "$CANDIDATE_COUNT" -eq 0 ]; then
    echo -e "${RED}ERROR: No resource group found. Run 'az group list -o table' to check.${NC}"
    exit 1
  else
    echo -e "${YELLOW}WARN: Multiple candidate resource groups found. Using the first one:${NC}"
    export TF_VAR_resource_group_name=$(echo "$CANDIDATES" | head -n 1)
    echo "  ${TF_VAR_resource_group_name}"
  fi
fi

# Handle --destroy
if [[ "${1:-}" == "--destroy" ]]; then
  echo
  echo -e "${YELLOW}WARNING: This will destroy only the Windows VM and its networking.${NC}"
  read -r -p "Type 'destroy' to confirm: " CONFIRM
  if [ "$CONFIRM" != "destroy" ]; then
    echo "Aborted."
    exit 1
  fi
  terraform -chdir="${STACK_DIR}" destroy -auto-approve
  rm -f "${REPO_ROOT}/vm-windows.rdp" "${REPO_ROOT}/vm-windows_credentials.txt"
  echo -e "${GREEN}Windows VM destroyed successfully.${NC}"
  exit 0
fi

# Handle --status
if [[ "${1:-}" == "--status" ]]; then
  echo
  echo "Checking Windows VM status..."
  if [ ! -f "${STACK_DIR}/terraform.tfstate" ]; then
    echo -e "${YELLOW}No deployment state found in windows-vm/ directory. Run './windows-vm.sh' to deploy.${NC}"
    exit 0
  fi
  VM_NAME=$(terraform -chdir="${STACK_DIR}" output -raw vm_name 2>/dev/null || echo "")
  RG_NAME=$(terraform -chdir="${STACK_DIR}" output -raw resource_group_name 2>/dev/null || echo "")
  PUBLIC_IP=$(terraform -chdir="${STACK_DIR}" output -raw public_ip 2>/dev/null || echo "")

  if [ -n "$VM_NAME" ]; then
    echo -e "${GREEN}✓ VM Name:${NC}    ${VM_NAME}"
    echo -e "${GREEN}✓ Public IP:${NC}  ${PUBLIC_IP}"
    az vm get-instance-view --resource-group "$RG_NAME" --name "$VM_NAME" \
      --query "{PowerState:instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus | [0], Provisioning:instanceView.statuses[?starts_with(code, 'ProvisioningState/')].displayStatus | [0]}" \
      -o table 2>/dev/null || true
  fi
  exit 0
fi

# 3. Deploy Windows VM
echo
echo -e "${CYAN}Initializing Terraform in windows-vm/...${NC}"
terraform -chdir="${STACK_DIR}" init -input=false

echo
echo -e "${CYAN}Applying Windows VM infrastructure (takes ~2-3 minutes)...${NC}"
terraform -chdir="${STACK_DIR}" apply -auto-approve

# 4. Post-deployment setup
RG_NAME=$(terraform -chdir="${STACK_DIR}" output -raw resource_group_name)
VM_NAME=$(terraform -chdir="${STACK_DIR}" output -raw vm_name)
PUBLIC_IP=$(terraform -chdir="${STACK_DIR}" output -raw public_ip)
ADMIN_USER=$(terraform -chdir="${STACK_DIR}" output -raw admin_username)
ADMIN_PASS=$(terraform -chdir="${STACK_DIR}" output -raw admin_password)

# Copy RDP and credentials file to root for convenience
if [ -f "${STACK_DIR}/${VM_NAME}.rdp" ]; then
  cp -f "${STACK_DIR}/${VM_NAME}.rdp" "${REPO_ROOT}/${VM_NAME}.rdp"
fi
if [ -f "${STACK_DIR}/${VM_NAME}_credentials.txt" ]; then
  cp -f "${STACK_DIR}/${VM_NAME}_credentials.txt" "${REPO_ROOT}/${VM_NAME}_credentials.txt"
  chmod 600 "${REPO_ROOT}/${VM_NAME}_credentials.txt"
fi

echo
echo -e "${GREEN}${BOLD}✓ Windows Server 2022 VM Deployed Successfully!${NC}"
echo
echo -e "${BOLD}==================== DEPLOYMENT SUMMARY ====================${NC}"
echo -e "${BOLD}Resource Group:${NC}      ${RG_NAME}"
echo -e "${BOLD}VM Name:${NC}             ${VM_NAME}"
echo -e "${BOLD}OS Version:${NC}          Windows Server 2022 Datacenter Azure Edition"
echo -e "${BOLD}VM Size:${NC}             Standard_B2s (2 vCPU, 4GB RAM)"
echo -e "${BOLD}Public IP:${NC}           ${PUBLIC_IP}"
echo -e "${BOLD}Admin Username:${NC}      ${ADMIN_USER}"
echo -e "${BOLD}Admin Password:${NC}      ${ADMIN_PASS}"
echo -e "${BOLD}RDP File:${NC}            ${REPO_ROOT}/${VM_NAME}.rdp"
echo -e "${BOLD}Credentials File:${NC}    ${REPO_ROOT}/${VM_NAME}_credentials.txt"
echo
echo -e "${BOLD}Connection Options:${NC}"
echo -e "  Remote Desktop:    mstsc /v:${PUBLIC_IP}"
echo -e "  Or double click:   ${VM_NAME}.rdp"
echo -e "  OpenSSH Login:     ssh ${ADMIN_USER}@${PUBLIC_IP}"
echo -e "  Check Status:      ./windows-vm.sh --status"
echo -e "  Destroy VM:        ./windows-vm.sh --destroy"
echo -e "${BOLD}============================================================${NC}"
