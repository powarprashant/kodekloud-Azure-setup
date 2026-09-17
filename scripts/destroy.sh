#!/usr/bin/env bash
# Confirmation-gated `terraform destroy`.
#
# WARNING: this removes every resource this Terraform state manages -
# the VM, ACR, AKS cluster, VNet/subnets/NSG, and (only if
# create_resource_group=true) the resource group itself. If you're
# using the KodeKloud Sandbox's pre-provisioned resource group
# (create_resource_group=false, the default), the resource group
# itself is left in place - only the resources Terraform created
# inside it are removed.
#
#   ./scripts/destroy.sh
set -uo pipefail

RED="\e[0;31m"
YELLOW="\e[0;33m"
NC="\e[0m"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo -e "${YELLOW}This will destroy every resource managed by this Terraform state:${NC}"
terraform state list 2>/dev/null || { echo -e "${RED}No terraform state found - nothing to destroy.${NC}"; exit 0; }

echo
read -r -p "Type 'destroy' to confirm: " CONFIRM
if [ "$CONFIRM" != "destroy" ]; then
  echo "Aborted. No changes made."
  exit 1
fi

terraform destroy

echo
echo "Destroy complete. Local generated files (SSH key, plan file) are not deleted automatically:"
echo "  rm -f *_ssh_key.pem tfplan.out"
