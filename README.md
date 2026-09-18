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
                     |                             + NSG (All Inbound Allowed)
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
| Network Security Group | Required | **All inbound traffic allowed** (`*` protocol, all ports) on the VM subnet for sandbox lab testing |
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

## 4. Independent Deployment Scripts (KodeKloud Sandbox Friendly)

You can run each component **completely separately** based on what you need to practice. Each has its own dedicated Terraform state and will not interfere with the others:

### 1) AKS & ACR: `./aks-setup.sh`
Provisions Azure Container Registry (ACR) and Azure Kubernetes Service (AKS) with `Standard_D2s_v3` nodes (strictly compliant with KodeKloud sandbox Azure Policy), `kubenet` networking, pre-configured `acr-secret` in Kubernetes, and auto-detects your sandbox resource group:
```bash
./aks-setup.sh            # Provision ACR & AKS
./aks-setup.sh --status   # Check cluster and node status
./aks-setup.sh --destroy  # Tear down only AKS & ACR
```

### 2) Ubuntu VM: `./ubuntu-vm.sh`
Provisions an Ubuntu 22.04 LTS VM (`Standard_B2s`, 2 vCPU, 4GB RAM) with **All Inbound Traffic allowed** in NSG (all ports/protocols open for lab and testing flexibility), with Docker, Docker Compose v2, Git, JQ, Kubectl, Azure CLI, and SonarQube kernel optimizations pre-configured:
```bash
./ubuntu-vm.sh            # Provision Ubuntu VM
./ubuntu-vm.sh --ssh      # SSH directly into the VM
./ubuntu-vm.sh --status   # Check VM status and public IP
./ubuntu-vm.sh --destroy  # Tear down only Ubuntu VM
```

### 3) Windows Server VM: `./windows-vm.sh`
Provisions a Windows Server 2022 Datacenter VM (`Standard_B2s` or `Standard_D2s_v3`) with **All Inbound Traffic allowed** in NSG and Windows Firewall (RDP 3389, OpenSSH 22, WinRM, and all web/app ports open for lab testing), auto-generated secure password, and ready-to-use `.rdp` connection shortcut:
```bash
./windows-vm.sh            # Provision Windows VM
./windows-vm.sh --status   # Check VM status and public IP
./windows-vm.sh --destroy  # Tear down only Windows VM
```

**Connecting to Windows VM:**
- **Double click:** Open the generated `vm-windows.rdp` file directly (pre-configured for full-screen session).
- **Windows mstsc:** `mstsc /v:<PUBLIC_IP>`
- **Linux:** `xfreerdp /v:<PUBLIC_IP> /u:azureuser /p:<PASSWORD>`
- **OpenSSH:** `ssh azureuser@<PUBLIC_IP>` (OpenSSH server is automatically configured)

---

## 5. All-in-One Deployment (Optional)

If you want to deploy everything at once using the root Terraform stack:

```bash
./scripts/setup.sh
terraform apply tfplan.out
```

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
