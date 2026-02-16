# Test Subscription Setup Guide

This guide describes how to deploy the **SRE Agent Demo Environment** for validating the optimization subagents. The demo environment uses **Azure Verified Module (AVM) Bicep templates** to deploy intentionally misconfigured or underutilized resources so that each subagent can detect and recommend optimizations.

> **Note:** This guide replaces the previous manual `az cli` setup. All resources are now deployed via Bicep IaC at [`infra/demo/`](../infra/demo/).

---

## Prerequisites

- An Azure subscription with Owner or Contributor role
- Azure CLI installed and authenticated (`az login`)
- Bicep CLI installed (`az bicep install` or `az bicep upgrade`)
- Sufficient quota in **swedencentral** for:
  - `Standard_D8s_v3` (1× VM — 8 vCPUs)
  - `Standard_D4s_v5` (1× VM — 4 vCPUs)
  - `Standard_D2s_v3` (1× VM — 2 vCPUs)
  - 1.5 TB managed disk capacity

---

## Quick Deploy

Use the deployment script to create all resources in one step:

```powershell
cd infra/demo
.\deploy-demo.ps1
```

The script will:
1. Run pre-flight checks (CLI version, Bicep version, subscription)
2. Auto-generate an SSH key pair if none exists
3. Deploy all resources to `rg-sre-demo-workloads` in **swedencentral**
4. Print a summary of deployed resources

### Manual Deploy (Alternative)

```powershell
az deployment sub create `
  --location swedencentral `
  --template-file infra/demo/main.bicep `
  --parameters infra/demo/main.parameters.json `
  --parameters sshPublicKey="$(Get-Content ~/.ssh/id_rsa.pub)"
```

---

## What Gets Deployed

All resources are deployed to resource group **`rg-sre-demo-workloads`** in **swedencentral**.

### Networking

| Resource | Type | Purpose |
|---|---|---|
| `vnet-sre-demo` | Virtual Network | 10.0.0.0/16 with `snet-workloads` subnet |
| `nsg-sre-demo` | Network Security Group | SSH allow + deny-all rules |

### Virtual Machines

All VMs have **auto-shutdown at 7:00 PM CET** (W. Europe Standard Time) to minimize costs.

| VM Name | SKU | Zone | Purpose / Expected Finding |
|---|---|---|---|
| `vm-oversized-v3` | Standard_D8s_v3 | 1 | **Rightsizing + gen upgrade** — 8 vCPU / 32 GB is oversized, v3→v5 upgrade recommended. 512 GB Premium OS disk is oversized. Tagged production/web-frontend. |
| `vm-devtest-nospotv5` | Standard_D4s_v5 | 1 | **Spot VM candidate** — Tagged development/ci-runner with `sla-required=false`. Agent should recommend converting to Spot with Deallocate eviction policy. |
| `vm-nozone-staging` | Standard_D2s_v3 | _(none)_ | **HA gap + gen upgrade** — No availability zone set. Old gen v3→v5. Tagged staging/api-backend. |

### Standalone Disks (Unattached / Orphaned)

| Disk Name | SKU | Size | Expected Finding |
|---|---|---|---|
| `disk-orphan-premium-512` | Premium_LRS | 512 GB | Unattached Premium disk = cost waste. Recommend deletion or snapshot + delete. |
| `disk-orphan-std-1024` | StandardSSD_LRS | 1 TB | Unattached large disk = cost waste. Recommend deletion. |

> **Additional orphan opportunity:** `vm-oversized-v3` has a 256 GB Premium data disk with `deleteOption: Detach`. If the VM is deleted, this disk becomes orphaned — testing the detach-on-delete scenario.

### Storage Accounts

| Storage Account | Tier | Lifecycle Policy | Expected Finding |
|---|---|---|---|
| `stsredemohotnolc` | Hot | ❌ None | Hot tier with no lifecycle management + open network (Allow). Agent should recommend adding lifecycle rules and restricting network access. |
| `stsredemolifecycle` | Cool | ✅ Cool@30d, Archive@90d, Delete@365d | Well-configured baseline. Agent should find few/no issues. |

---

## Resource-to-Scenario Mapping

Each demo resource maps to test scenarios in [`tests/scenarios/`](scenarios/):

| Demo Resource | Test Scenario | Scenario File |
|---|---|---|
| `vm-oversized-v3` (D8s_v3, low util) | Oversized VM detection + downsizing | [`scenarios/oversized-vm.md`](scenarios/oversized-vm.md) |
| `vm-oversized-v3` (1 data disk, detach) | Hard constraint on disk count if downsized | [`scenarios/hard-constraint.md`](scenarios/hard-constraint.md) |
| `vm-devtest-nospotv5` (D4s_v5, dev) | Alternative SKU / Spot recommendation | [`scenarios/alternative-sku.md`](scenarios/alternative-sku.md) |
| `vm-nozone-staging` (no AMA) | Missing metrics handling | [`scenarios/missing-metrics.md`](scenarios/missing-metrics.md) |
| Any VM after 30+ days deallocated | Deallocated VM detection | [`scenarios/deallocated-vm.md`](scenarios/deallocated-vm.md) |

---

## Post-Deployment Steps

### 1. Verify Resources

```powershell
# List all resources in the demo resource group
az resource list --resource-group rg-sre-demo-workloads --output table

# Verify VM power states
az vm list --resource-group rg-sre-demo-workloads --show-details --output table
```

### 2. Install Azure Monitor Agent (Selective)

Install AMA on **some** VMs to test the contrast between VMs with and without metrics:

```powershell
# Install AMA on the oversized VM and dev/test VM only
# Do NOT install on vm-nozone-staging to test missing metrics scenario
az vm extension set `
  --resource-group rg-sre-demo-workloads `
  --vm-name vm-oversized-v3 `
  --name AzureMonitorLinuxAgent `
  --publisher Microsoft.Azure.Monitor `
  --enable-auto-upgrade true

az vm extension set `
  --resource-group rg-sre-demo-workloads `
  --vm-name vm-devtest-nospotv5 `
  --name AzureMonitorLinuxAgent `
  --publisher Microsoft.Azure.Monitor `
  --enable-auto-upgrade true
```

> **Important:** Do NOT install AMA on `vm-nozone-staging` — this VM tests the missing metrics scenario.

### 3. Create a Log Analytics Workspace (Optional)

For full VM Insights metrics (memory, disk IOPS at guest level):

```powershell
az monitor log-analytics workspace create `
  --resource-group rg-sre-demo-workloads `
  --workspace-name law-sre-demo `
  --location swedencentral
```

### 4. Wait for Advisor Recommendations

Azure Advisor typically takes **24–48 hours** to generate right-sizing recommendations for underutilized VMs:

```powershell
az advisor recommendation list `
  --resource-group rg-sre-demo-workloads `
  --category Cost
```

### 5. Simulate a Deallocated VM (Optional)

To test the deallocated VM scenario, stop one of the VMs:

```powershell
# Deallocate VM3 to simulate a long-idle VM
az vm deallocate --resource-group rg-sre-demo-workloads --name vm-nozone-staging

# After 30+ days, the agent should flag this for deletion
# For PoC testing, validate the Activity Log query logic directly:
az monitor activity-log list `
  --resource-group rg-sre-demo-workloads `
  --offset 30d `
  --query "[?contains(resourceId, 'vm-nozone-staging') && operationName.value=='Microsoft.Compute/virtualMachines/start/action']"
```

---

## Expected Cost

| Resource | SKU / Tier | Est. Monthly Cost |
|---|---|---|
| `vm-oversized-v3` | Standard_D8s_v3 | ~$280 |
| `vm-devtest-nospotv5` | Standard_D4s_v5 | ~$140 |
| `vm-nozone-staging` | Standard_D2s_v3 | ~$70 |
| `disk-orphan-premium-512` | Premium_LRS 512 GB | ~$73 |
| `disk-orphan-std-1024` | StandardSSD_LRS 1 TB | ~$77 |
| `vm-oversized-v3` OS + data disks | Premium 512 GB + 256 GB | ~$109 |
| Storage accounts (2×) | Standard_LRS | ~$2 |
| **Total (running)** | | **~$745/month** |
| **Total (deallocated)** | | **~$255/month** |

> **Cost-saving tips:**
> - Auto-shutdown is configured at **7:00 PM CET** daily on all VMs
> - Deallocate all VMs when not testing: `az vm deallocate -g rg-sre-demo-workloads --ids $(az vm list -g rg-sre-demo-workloads --query "[].id" -o tsv)`
> - Daily running cost: ~$24/day | 2-hour demo session: ~$2

---

## Cleanup

```powershell
# Delete entire resource group when testing is complete
az group delete --name rg-sre-demo-workloads --yes --no-wait
```

---

## IaC Files Reference

| File | Description |
|---|---|
| [`infra/demo/main.bicep`](../infra/demo/main.bicep) | Subscription-scoped entry point |
| [`infra/demo/modules/demo-resources.bicep`](../infra/demo/modules/demo-resources.bicep) | All resources using AVM modules |
| [`infra/demo/main.parameters.json`](../infra/demo/main.parameters.json) | Parameter values |
| [`infra/demo/deploy-demo.ps1`](../infra/demo/deploy-demo.ps1) | Automated deployment script |

---

## Migration from Old Manual Setup

If you previously used the manual `az cli` bash-based setup (`rg-sre-agent-test` in `eastus`), here is the mapping to the new Bicep resources:

| Old Resource (Manual) | New Resource (Bicep) | Notes |
|---|---|---|
| `vm-oversized-test` (D8s_v5) | `vm-oversized-v3` (D8s_v3) | Now uses v3 to also test gen-upgrade recommendation |
| `vm-maxdisks-test` (D8s_v5 + 7 disks) | `vm-oversized-v3` (1 data disk, detach) | Simplified; hard-constraint tested via FitScore logic |
| `vm-deallocated-test` (B2s) | `vm-nozone-staging` (D2s_v3, deallocate manually) | Deallocate post-deploy to test idle VM detection |
| `vm-stopped-test` (B2s) | _(not in demo)_ | Test via E2E simulation mock data |
| `vm-no-insights-test` (D4s_v5) | `vm-nozone-staging` (no AMA installed) | Skip AMA install to test missing metrics |
| `disk-unattached-test` (128 GB) | `disk-orphan-premium-512` (512 GB) | Larger disk = more visible cost waste |
| `disk-overprovisioned-test` (1 TB) | `disk-orphan-std-1024` (1 TB) | Same size, StandardSSD instead of Premium |
| `lb-empty-test` | _(not in demo)_ | Network scenarios deferred to future phase |
| `nsg-orphaned-test` | _(not in demo)_ | NSG is attached to subnet in demo |
| `pip-orphaned-test` | _(not in demo)_ | Network scenarios deferred |
| `asp-oversized-test` (P2v3) | _(not in demo)_ | PaaS scenarios deferred to future phase |

> **Note:** The old `rg-sre-agent-test` resource group should be deleted if it still exists.
