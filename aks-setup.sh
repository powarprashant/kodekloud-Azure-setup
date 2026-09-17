#!/usr/bin/env bash
# ==============================================================================
# aks-setup.sh
# 
# One-shot provisioning of ACR (Azure Container Registry) and AKS (Azure
# Kubernetes Service) designed specifically for KodeKloud Azure Sandboxes.
#
# Usage:
#   ./aks-setup.sh            # Provision ACR & AKS
#   ./aks-setup.sh --status   # Check status and node health
#   ./aks-setup.sh --destroy  # Tear down ACR & AKS only
# ==============================================================================

set -euo pipefail

RED="\e[0;31m"
GREEN="\e[0;32m"
YELLOW="\e[0;33m"
CYAN="\e[0;36m"
BOLD="\e[1m"
NC="\e[0m"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="${REPO_ROOT}/aks"

echo -e "${CYAN}${BOLD}=== KodeKloud Azure Sandbox: AKS & ACR Setup ===${NC}"
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
  echo -e "${YELLOW}WARNING: This will destroy only the AKS cluster, ACR registry, and AKS VNet.${NC}"
  read -r -p "Type 'destroy' to confirm: " CONFIRM
  if [ "$CONFIRM" != "destroy" ]; then
    echo "Aborted."
    exit 1
  fi
  terraform -chdir="${STACK_DIR}" destroy -auto-approve
  echo -e "${GREEN}AKS & ACR resources destroyed successfully.${NC}"
  exit 0
fi

# Handle --status
if [[ "${1:-}" == "--status" ]]; then
  echo
  echo "Checking AKS & ACR deployment status..."
  if [ ! -f "${STACK_DIR}/terraform.tfstate" ]; then
    echo -e "${YELLOW}No deployment state found in aks/ directory. Run './aks-setup.sh' to deploy.${NC}"
    exit 0
  fi
  AKS_NAME=$(terraform -chdir="${STACK_DIR}" output -raw aks_cluster_name 2>/dev/null || echo "")
  ACR_NAME=$(terraform -chdir="${STACK_DIR}" output -raw acr_name 2>/dev/null || echo "")
  RG_NAME=$(terraform -chdir="${STACK_DIR}" output -raw resource_group_name 2>/dev/null || echo "")

  if [ -n "$AKS_NAME" ]; then
    echo -e "${GREEN}✓ AKS Cluster:${NC} ${AKS_NAME}"
    az aks show --resource-group "$RG_NAME" --name "$AKS_NAME" --query "{Name:name, ProvisioningState:provisioningState, PowerState:powerState.code, KubeVersion:kubernetesVersion}" -o table 2>/dev/null || true
    if command -v kubectl >/dev/null 2>&1; then
      az aks get-credentials --resource-group "$RG_NAME" --name "$AKS_NAME" --overwrite-existing >/dev/null 2>&1 || true
      echo -e "\n${BOLD}Nodes:${NC}"
      kubectl get nodes -o wide 2>/dev/null || echo "Unable to query nodes."
    fi
  fi
  if [ -n "$ACR_NAME" ]; then
    echo -e "\n${GREEN}✓ ACR Registry:${NC} ${ACR_NAME}"
    az acr show --name "$ACR_NAME" --query "{Name:name, LoginServer:loginServer, SKU:sku.name}" -o table 2>/dev/null || true
  fi
  exit 0
fi

# 3. Deploy AKS & ACR
echo
echo -e "${CYAN}Initializing Terraform in aks/...${NC}"
terraform -chdir="${STACK_DIR}" init -input=false

echo
echo -e "${CYAN}Applying AKS and ACR infrastructure (takes ~4-6 minutes in Azure)...${NC}"
terraform -chdir="${STACK_DIR}" apply -auto-approve

# 4. Post-deployment setup
echo
echo -e "${GREEN}${BOLD}✓ Infrastructure Provisioned Successfully!${NC}"
echo

RG_NAME=$(terraform -chdir="${STACK_DIR}" output -raw resource_group_name)
AKS_NAME=$(terraform -chdir="${STACK_DIR}" output -raw aks_cluster_name)
ACR_NAME=$(terraform -chdir="${STACK_DIR}" output -raw acr_name)
ACR_SERVER=$(terraform -chdir="${STACK_DIR}" output -raw acr_login_server)
ACR_USER=$(terraform -chdir="${STACK_DIR}" output -raw acr_admin_username)
ACR_PASS=$(terraform -chdir="${STACK_DIR}" output -raw acr_admin_password)

# Fetch kubeconfig
echo -e "${CYAN}Configuring kubectl credentials...${NC}"
az aks get-credentials --resource-group "${RG_NAME}" --name "${AKS_NAME}" --overwrite-existing

if command -v kubectl >/dev/null 2>&1; then
  echo -e "\n${GREEN}Node Status:${NC}"
  kubectl get nodes -o wide || true

  echo
  echo -e "${CYAN}Creating Kubernetes secret 'acr-secret' for ACR image pulls...${NC}"
  kubectl create secret docker-registry acr-secret \
    --docker-server="${ACR_SERVER}" \
    --docker-username="${ACR_USER}" \
    --docker-password="${ACR_PASS}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 && \
    echo -e "${GREEN}✓ Created 'acr-secret' in default namespace.${NC}" || true
else
  echo -e "${YELLOW}Note: kubectl not found locally. Install it to manage your AKS cluster.${NC}"
fi

# Print connection details
echo
echo -e "${BOLD}==================== DEPLOYMENT SUMMARY ====================${NC}"
echo -e "${BOLD}Resource Group:${NC}      ${RG_NAME}"
echo -e "${BOLD}AKS Cluster:${NC}         ${AKS_NAME}"
echo -e "${BOLD}ACR Name:${NC}            ${ACR_NAME}"
echo -e "${BOLD}ACR Login Server:${NC}    ${ACR_SERVER}"
echo -e "${BOLD}ACR Username:${NC}        ${ACR_USER}"
echo -e "${BOLD}ACR Password:${NC}        ${ACR_PASS}"
echo
echo -e "${BOLD}Useful Commands:${NC}"
echo -e "  Connect cluster:   az aks get-credentials --resource-group ${RG_NAME} --name ${AKS_NAME}"
echo -e "  Check cluster:     kubectl get nodes"
echo -e "  Login to ACR:      az acr login --name ${ACR_NAME}"
echo -e "  Check status:      ./aks-setup.sh --status"
echo -e "  Destroy cluster:   ./aks-setup.sh --destroy"
echo -e "${BOLD}============================================================${NC}"
