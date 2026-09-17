# KodeKloud Azure Sandbox Notes

This repo is designed to deploy cleanly inside a permission-restricted
KodeKloud Azure Sandbox subscription. This page documents the specific
constraints it works around and how to recognize/handle each one.

## Resource Group

The sandbox pre-provisions exactly one resource group for you (commonly
named like `ODL-azure-XXXXXXXX`) and blocks
`Microsoft.Resources/subscriptions/resourceGroups/write` for new ones.

- Default (`create_resource_group = false`): the `resource-group` module
  looks up the resource group named in `var.resource_group_name`. The
  azurerm provider has no "list all resource groups" data source, so
  auto-detection of that name happens in `./scripts/setup.sh`, which
  queries `az group list`, excludes system-managed groups
  (`NetworkWatcherRG`, `MC_*`, `DefaultResourceGroup-*`,
  `cloud-shell-storage-*`), and exports `TF_VAR_resource_group_name`
  before running `terraform plan`.
- Running plain `terraform plan`/`apply` (without `./scripts/setup.sh`)
  requires `resource_group_name` to be set explicitly in
  `terraform.tfvars` - find it with:
  ```bash
  az group list -o table
  ```
- If auto-detection finds more than one candidate resource group, the
  script warns and lists them; set `resource_group_name` explicitly in
  that case.
- On a personal/full-permission subscription, set
  `create_resource_group = true` to have Terraform create and own the
  resource group instead.

## AKS \<-\> ACR image pulls (role assignment)

Proper AKS-to-ACR integration uses an `AcrPull` role assignment against the
AKS kubelet identity, which requires
`Microsoft.Authorization/roleAssignments/write`. Sandbox subscriptions
commonly block this for regular users.

- Default (`enable_acr_role_assignment = false`): Terraform does **not**
  attempt the role assignment. `acr_admin_enabled = true` (also default)
  enables ACR's admin username/password instead, which pods can use as a
  Kubernetes `imagePullSecret`:
  ```bash
  ACR_NAME=$(terraform output -raw acr_name)
  ACR_SERVER=$(terraform output -raw acr_login_server)
  ACR_USER=$(az acr credential show --name "$ACR_NAME" --query username -o tsv)
  ACR_PASS=$(az acr credential show --name "$ACR_NAME" --query passwords[0].value -o tsv)

  kubectl create secret docker-registry acr-pull-secret \
    --docker-server="$ACR_SERVER" \
    --docker-username="$ACR_USER" \
    --docker-password="$ACR_PASS"
  ```
  Then reference `imagePullSecrets: [{name: acr-pull-secret}]` in your pod
  spec (see `examples/nginx/deployment.yaml`).
- If your subscription does allow role assignments, set
  `enable_acr_role_assignment = true` and Terraform creates the
  `AcrPull` assignment automatically - no manual secret needed.
- `az aks update --attach-acr <acr-name>` is the usual "just do it for me"
  command, but it performs the same role assignment under the hood and
  will fail with `AuthorizationFailed` under the same restriction -
  **UNVERIFIED** whether any sandbox tier allows this command specifically.

## VM identity and permissions

The VM has its own `SystemAssigned` managed identity (`module.vm.principal_id`),
created unconditionally - identity creation itself needs no special
permission. It starts with **no role assignments**, so it cannot call any
Azure API by default.

- `vm_enable_acr_role_assignment = true` grants that identity `AcrPull` on
  the registry, mirroring the AKS pattern above - same
  `Microsoft.Authorization/roleAssignments/write` requirement, same
  sandbox restriction, off by default.
- For anything beyond ACR pulls (Key Vault, storage, etc.), grant the role
  manually against `vm_principal_id` once you know your subscription
  allows it:
  ```bash
  az role assignment create \
    --assignee "$(terraform output -raw vm_principal_id)" \
    --role "<role-name>" \
    --scope "<resource-id>"
  ```

### Why this differs from AWS IAM roles

AWS EKS requires you to explicitly create and attach IAM roles
(`eksClusterRole`, `eksWorkerNodeRole`) with managed policies
(`AmazonEKSClusterPolicy`, `AmazonEKSWorkerNodePolicy`, etc.) because EKS
does not provision any IAM for you. AKS's control-plane and kubelet
identities are auto-created and get what they need on the auto-managed
node resource group (`MC_*`) **internally, via the AKS resource
provider's own permissions** - not through a Terraform-managed role
assignment the caller has to create. The only *caller-initiated* role
assignments in this repo are the two ACR-pull grants above, and both are
opt-in precisely because they are the one place this design intersects
with the sandbox's `roleAssignments/write` restriction.

## Networking: kubenet vs Azure CNI

`aks_network_plugin` defaults to `kubenet`. Azure CNI (`azure`) assigns
every pod a routable IP from the subnet, which:
- consumes far more subnet address space per node than kubenet, and
- in some environments requires the AKS identity to have `Network
  Contributor` (or equivalent) on the subnet/VNet, which is itself a role
  assignment and may be blocked for the same reason as above.

kubenet avoids both problems and is the safer default for a small sandbox
subnet. Azure CNI is exposed as an option for subscriptions with more
permissive networking. **This tradeoff is UNVERIFIED against the current
KodeKloud sandbox specifically** - test with a plan before relying on it.

## Common errors and what they mean

| Error | Likely cause | What to do |
|---|---|---|
| `AuthorizationFailed` | Your sandbox identity lacks a permission for that operation (often `roleAssignments/write` or `resourceGroups/write`) | Check which resource triggered it; if it's the AcrPull role assignment or resource group creation, use the fallbacks above |
| `QuotaExceeded` | Sandbox subscription has a core/resource quota lower than what you requested | Reduce `aks_system_node_count`, avoid `aks_enable_user_node_pool`, or pick a smaller `vm_size`/`aks_vm_size` |
| `SKUNotAvailable` | The chosen VM size isn't offered in `var.location` for this subscription | Try a different size (`Standard_B1s`/`Standard_B2s` are broadly available) or a different region |
| `ResourceProviderNotRegistered` | `Microsoft.ContainerService`, `Microsoft.ContainerRegistry`, `Microsoft.Compute`, or `Microsoft.Network` isn't registered on the subscription | Try `az provider register --namespace Microsoft.ContainerService` (etc.) - if that itself fails with `AuthorizationFailed`, the sandbox likely pre-registers what it allows; retry the apply, since many sandboxes auto-register on first use |
| `InsufficientFreeAddresses` | The AKS or VM subnet ran out of IPs (common with Azure CNI) | Use `kubenet`, shrink `aks_system_node_count`, or widen the subnet's address prefix |
| `RoleAssignmentFailed` | Same root cause as `AuthorizationFailed` on a role assignment | Same fallback: disable the role assignment, use the ACR admin-credential path |
| `InvalidTemplateDeployment` / `OperationNotAllowed` | Sandbox policy blocking a specific resource property (e.g. disk SKU, VM size tier) | Read the inner error message it wraps - it usually names the exact blocked property |

## Resources deliberately NOT used

Private Endpoints, Azure Firewall, NAT Gateway, Application Gateway,
Bastion, Premium ACR, Log Analytics/Container Insights, and complex Key
Vault/Private DNS configurations are all omitted by design. None are
required for this lab's architecture, and each is a common source of
`AuthorizationFailed`/quota problems in a restricted sandbox.
