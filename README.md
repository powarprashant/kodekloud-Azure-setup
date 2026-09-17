# kodekloud-azure-setup

Terraform for a complete Azure DevOps lab environment, designed to deploy
cleanly inside a **KodeKloud Azure Sandbox**: one repo, one `terraform
apply`, a working VM + ACR + AKS cluster with sizes and features chosen to
minimize quota/permission problems.

This is the Azure counterpart to
[kodekloud-eks-setup](https://github.com/powarprashant/kodekloud-eks-setup),
following the same philosophy: reuse what the sandbox already gives you,
create only what you actually need, and keep every sandbox-specific
decision visible in `variables.tf` rather than hidden in code.

## 1. Architecture

```text
                              Azure Subscription
                                     |
                    Resource Group (reused from sandbox by default)
                                     |
                                    VNet
                                     |
                    +----------------+----------------+
                    |                                 |
              AKS Subnet                         VM Subnet
                    |                                 |
                   AKS                          Azure VM (Ubuntu)
                    |                             + NSG (SSH only)
             +------+------+                      + Public IP
             |             |
        System Node    User Node Pool
           Pool           (optional)
             |
             +------------------+
                                |
                               ACR  <--- AcrPull role assignment (optional)
                                |         or admin-credential imagePullSecret
                            Container
                             Images
```

### What gets created

| Resource | Required? | Notes |
|---|---|---|
| Resource Group | Required | **Reused** from the sandbox by default, not created (`create_resource_group=false`) |
| Virtual Network + 2 Subnets | Required | One subnet for AKS, one for the VM |
| Network Security Group | Required | SSH (22) inbound allow on the VM subnet only |
| Public IP | Required (VM) | Can be disabled via `vm_enable_public_ip=false` |
| Linux VM (Ubuntu 22.04) | Required | `Standard_B1s` by default, with a `SystemAssigned` managed identity |
| Azure Container Registry | Required | Basic SKU |
| AKS cluster (system node pool) | Required | `Standard_B2s`, kubenet networking, SystemAssigned identity |
| AKS user node pool | Optional | Off by default (`aks_enable_user_node_pool=false`) |
| AKS -> ACR role assignment (`AcrPull`) | Optional | Off by default - sandbox usually blocks role assignment writes; see [docs/sandbox-notes.md](docs/sandbox-notes.md) for the fallback |
| Log Analytics, Private Endpoints, Firewall, NAT Gateway, App Gateway, Bastion | **Not created** | Unnecessary for this lab and common sources of `AuthorizationFailed`/quota errors in a sandbox |

## 2. Prerequisites

- Access to a **KodeKloud Azure Sandbox** (or any Azure subscription)
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az`)
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [kubectl](https://kubernetes.io/docs/tasks/tools/) (only needed after AKS is up)
- An SSH key pair, or let Terraform generate one for you

## 3. Authentication

This repo authenticates via your Azure CLI session - no service principal,
client secret, or credentials file is stored anywhere in this repo or in
Terraform state.

```bash
az login
az account show
az account set --subscription "<SUBSCRIPTION_ID>"   # only if you have more than one
```

## 4. Deployment

```bash
git clone <this-repo-url>
cd kodekloud-azure-setup

az login

terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Or use the wrapper, which runs the same preflight + init/fmt/validate/plan
and stops before applying:

```bash
./scripts/setup.sh
terraform apply tfplan.out
```

All variables have KodeKloud Sandbox-friendly defaults (see
`variables.tf`), so you can deploy with no `terraform.tfvars` at all. To
override anything, copy `terraform.tfvars.example` to `terraform.tfvars`
and uncomment what you need.

## 5. Verify

```bash
az group list -o table
az vm list -o table
az acr list -o table
az aks list -o table

az aks get-credentials --resource-group "$(terraform output -raw resource_group_name)" --name "$(terraform output -raw aks_cluster_name)"
kubectl get nodes
```

Or run the non-destructive status check:

```bash
./scripts/verify.sh
```

## 6. Connect to the VM

```bash
terraform output vm_public_ip
ssh -i "$(terraform output -raw ssh_private_key_path)" azureuser@$(terraform output -raw vm_public_ip)
```

(`ssh_private_key_path` is only set if Terraform generated the key for
you - i.e. you left `ssh_public_key` blank. If you supplied your own
public key, use your own matching private key instead.)

## 7. Connect to AKS

```bash
az aks get-credentials \
  --resource-group "$(terraform output -raw resource_group_name)" \
  --name "$(terraform output -raw aks_cluster_name)"

kubectl get nodes
kubectl get pods -A
```

## 8. Test ACR

```bash
ACR_NAME=$(terraform output -raw acr_name)
ACR_SERVER=$(terraform output -raw acr_login_server)

az acr login --name "$ACR_NAME"

docker pull nginx:latest
docker tag nginx:latest "${ACR_SERVER}/nginx:latest"
docker push "${ACR_SERVER}/nginx:latest"
```

To actually run that image on AKS, see
[examples/nginx](examples/nginx) - it documents both the direct
role-assignment path and the ACR-admin-credential fallback used when role
assignments are blocked (the KodeKloud Sandbox default here).

## 9. Destroy

```bash
terraform destroy
```

or, with a confirmation prompt:

```bash
./scripts/destroy.sh
```

If `create_resource_group=false` (the default), the resource group itself
is **not** deleted - only the VNet, VM, ACR, and AKS cluster Terraform
created inside it. If you set `create_resource_group=true`, destroying
also removes the resource group.

## 10. Troubleshooting

See [docs/sandbox-notes.md](docs/sandbox-notes.md) for a full breakdown of
KodeKloud Sandbox constraints, including a table of common errors
(`AuthorizationFailed`, `QuotaExceeded`, `SKUNotAvailable`,
`ResourceProviderNotRegistered`, `InsufficientFreeAddresses`,
`RoleAssignmentFailed`, etc.), what causes each one here, and the exact
workaround.

## Repository layout

```text
kodekloud-azure-setup/
├── README.md
├── LICENSE
├── .gitignore
├── providers.tf
├── versions.tf
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example
├── modules/
│   ├── resource-group/   # create-or-reuse the sandbox resource group
│   ├── network/          # VNet, subnets, NSG
│   ├── vm/                # Linux VM, NIC, public IP
│   ├── acr/               # Container registry
│   └── aks/               # AKS cluster + optional AcrPull role assignment
├── scripts/
│   ├── setup.sh    # preflight + init/fmt/validate/plan
│   ├── verify.sh   # non-destructive status check
│   └── destroy.sh  # confirmation-gated terraform destroy
├── docs/
│   └── sandbox-notes.md
└── examples/
    └── nginx/      # optional ACR -> AKS smoke test, applied manually
```
