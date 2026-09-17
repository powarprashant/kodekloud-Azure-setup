#!/usr/bin/env bash
# ==============================================================================
# ubuntu-vm.sh
# 
# One-shot provisioning of an Ubuntu 22.04 LTS VM with Docker, Docker Compose,
# and DevOps tools pre-installed. Designed specifically for KodeKloud Azure Sandbox.
#
# Usage:
#   ./ubuntu-vm.sh            # Provision Ubuntu VM
#   ./ubuntu-vm.sh --ssh      # SSH directly into the VM
#   ./ubuntu-vm.sh --status   # Check VM power state and IP
#   ./ubuntu-vm.sh --destroy  # Tear down Ubuntu VM only
# ==============================================================================

set -uo pipefail

RED="\e[0;31m"
GREEN="\e[0;32m"
YELLOW="\e[0;33m"
CYAN="\e[0;36m"
BOLD="\e[1m"
NC="\e[0m"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="${REPO_ROOT}/ubuntu-vm"

echo -e "${CYAN}${BOLD}=== KodeKloud Azure Sandbox: Ubuntu VM Setup ===${NC}"
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
  echo -e "${YELLOW}WARNING: This will destroy only the Ubuntu VM and its networking.${NC}"
  read -r -p "Type 'destroy' to confirm: " CONFIRM
  if [ "$CONFIRM" != "destroy" ]; then
    echo "Aborted."
    exit 1
  fi
  terraform -chdir="${STACK_DIR}" destroy -auto-approve
  rm -f "${REPO_ROOT}/vm-ubuntu_key.pem"
  echo -e "${GREEN}Ubuntu VM destroyed successfully.${NC}"
  exit 0
fi

# Handle --ssh
if [[ "${1:-}" == "--ssh" ]]; then
  if [ ! -f "${STACK_DIR}/terraform.tfstate" ]; then
    echo -e "${RED}ERROR: No deployed VM found. Run './ubuntu-vm.sh' to provision first.${NC}"
    exit 1
  fi
  PUBLIC_IP=$(terraform -chdir="${STACK_DIR}" output -raw public_ip 2>/dev/null || echo "")
  KEY_FILE="${STACK_DIR}/vm-ubuntu_key.pem"
  if [ ! -f "$KEY_FILE" ]; then
    KEY_FILE="${REPO_ROOT}/vm-ubuntu_key.pem"
  fi
  if [ -z "$PUBLIC_IP" ] || [ ! -f "$KEY_FILE" ]; then
    echo -e "${RED}ERROR: VM IP or private key not found.${NC}"
    exit 1
  fi
  chmod 600 "$KEY_FILE"
  echo -e "${CYAN}Connecting to azureuser@${PUBLIC_IP}...${NC}"
  ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no "azureuser@${PUBLIC_IP}"
  exit 0
fi

# Handle --status
if [[ "${1:-}" == "--status" ]]; then
  echo
  echo "Checking Ubuntu VM status..."
  if [ ! -f "${STACK_DIR}/terraform.tfstate" ]; then
    echo -e "${YELLOW}No deployment state found in ubuntu-vm/ directory. Run './ubuntu-vm.sh' to deploy.${NC}"
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

# 3. Deploy Ubuntu VM
echo
echo -e "${CYAN}Initializing Terraform in ubuntu-vm/...${NC}"
terraform -chdir="${STACK_DIR}" init -input=false

echo
echo -e "${CYAN}Applying Ubuntu VM infrastructure (takes ~1-2 minutes)...${NC}"
terraform -chdir="${STACK_DIR}" apply -auto-approve

# 4. Post-deployment setup
RG_NAME=$(terraform -chdir="${STACK_DIR}" output -raw resource_group_name)
VM_NAME=$(terraform -chdir="${STACK_DIR}" output -raw vm_name)
PUBLIC_IP=$(terraform -chdir="${STACK_DIR}" output -raw public_ip)
KEY_FILE="${STACK_DIR}/${VM_NAME}_key.pem"

# Copy key to root for easy access
if [ -f "$KEY_FILE" ]; then
  cp -f "$KEY_FILE" "${REPO_ROOT}/${VM_NAME}_key.pem"
  chmod 600 "${REPO_ROOT}/${VM_NAME}_key.pem"
  chmod 600 "$KEY_FILE"
fi

echo
echo -e "${GREEN}${BOLD}✓ Ubuntu VM Deployed Successfully!${NC}"
echo
echo -e "${BOLD}==================== DEPLOYMENT SUMMARY ====================${NC}"
echo -e "${BOLD}Resource Group:${NC}      ${RG_NAME}"
echo -e "${BOLD}VM Name:${NC}             ${VM_NAME}"
echo -e "${BOLD}VM Size:${NC}             Standard_B2s (2 vCPU, 4GB RAM)"
echo -e "${BOLD}Public IP:${NC}           ${PUBLIC_IP}"
echo -e "${BOLD}SSH User:${NC}            azureuser"
echo -e "${BOLD}Private Key:${NC}         ${REPO_ROOT}/${VM_NAME}_key.pem"
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
echo -e "  Manual SSH:        ssh -i ${VM_NAME}_key.pem azureuser@${PUBLIC_IP}"
echo -e "  Check Status:      ./ubuntu-vm.sh --status"
echo -e "  Destroy VM:        ./ubuntu-vm.sh --destroy"
echo -e "${BOLD}============================================================${NC}"
