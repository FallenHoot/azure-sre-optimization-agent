# Test Scenario: Missing VM Insights Metrics

## Objective

Validate that the compute optimization subagent correctly handles VMs without Azure Monitor Agent (AMA) installed, resulting in missing memory metrics, appropriate FitScore penalty, and a data gap note in the recommendation.

---

## Demo Resource

| Property | Value |
|---|---|
| **VM Name** | `vm-nozone-staging` |
| **Resource Group** | `rg-sre-demo-workloads` |
| **Region** | swedencentral |
| **SKU** | Standard_D2s_v3 (2 vCPU / 8 GiB) |
| **OS Disk** | 128 GB StandardSSD_LRS |
| **Tags** | `environment=staging`, `workload=api-backend` |
| **AMA Installed** | ❌ No — intentionally omitted |
| **Deployed By** | [`infra/demo/modules/demo-resources.bicep`](../../infra/demo/modules/demo-resources.bicep) — module `vm3` |

> **Important:** Do NOT install AMA on `vm-nozone-staging`. AMA is installed on `vm-oversized-v3` and `vm-devtest-nospotv5` for contrast.

---

## Setup

Deploy the demo environment and install AMA on the other VMs only:

```powershell
cd infra/demo
.\deploy-demo.ps1

# Install AMA on vm-oversized-v3 and vm-devtest-nospotv5 ONLY
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

# Do NOT run this for vm-nozone-staging!
```

### Verify AMA Is NOT Installed

```powershell
az vm extension list `
  --resource-group rg-sre-demo-workloads `
  --vm-name vm-nozone-staging `
  --query "[?contains(name, 'AzureMonitor')].name" `
  --output tsv
```

Expected output: _(empty — no AMA extension)_

### Verify Memory Metrics Are Unavailable

```powershell
az monitor metrics list `
  --resource $(az vm show -g rg-sre-demo-workloads -n vm-nozone-staging --query id -o tsv) `
  --metric "Available MBytes Memory" `
  --interval PT1H `
  --output table
```

Expected: No data or error indicating the metric is not available.

---

## What Metrics Are Available vs Missing

| Metric | Source | Available Without AMA? |
|---|---|---|
| CPU Percentage | Azure Platform (host) | ✅ Yes |
| Available Memory (MBytes) | VM Insights (guest) | ❌ No |
| Disk Read/Write IOPS | Azure Platform (host) | ✅ Yes (at disk level) |
| Disk Read/Write MiBps | Azure Platform (host) | ✅ Yes (at disk level) |
| Network In/Out | Azure Platform (host) | ✅ Yes |

---

## Expected Results

| Check | Expected |
|---|---|
| CPU metrics available | Yes (platform-level) |
| Memory metrics available | **No** (requires AMA / VM Insights) |
| Subagent detects missing metrics | Yes |
| FitScore penalty | -0.5 for missing data |
| Data gap noted in output | Yes |
| Recommendation still generated | Yes (with reduced confidence) |

### Expected FitScore Calculation

Assuming Advisor recommends a smaller SKU and CPU/IOPS/network are within limits:

```
Base Score:                    5.0
Hard Constraints (Disk/NIC):   PASS
CPU Check (e.g., 20% vs 80%): PASS — no penalty
Memory Check:                  N/A — data unavailable → -0.5
IOPS Check:                    PASS — no penalty
MiBps Check:                   PASS — no penalty
Network Check:                 PASS — no penalty
─────────────────────────────────────
Final FitScore:                4.5
Data Quality:                  DEGRADED — missing memory metrics
```

---

## Expected Subagent Output

```markdown
## vm-nozone-staging (Standard_D2s_v3 → Standard_D2s_v5)

- **FitScore:** 4.5 / 5.0 ⚠️
- **Savings:** ~$10–20/month (gen upgrade)
- **Risk:** Medium — missing memory metrics reduce confidence
- **Action:** Right-size / gen-upgrade (with caveat)

### ⚠️ Data Quality Warning
Memory metrics are unavailable for this VM. Azure Monitor Agent (AMA) is not installed.
FitScore has been reduced by 0.5 due to incomplete data.

**Recommendation:** Install AMA and wait 7 days for memory baseline before resizing.

### Install AMA Command
az vm extension set `
  --resource-group rg-sre-demo-workloads `
  --vm-name vm-nozone-staging `
  --name AzureMonitorLinuxAgent `
  --publisher Microsoft.Azure.Monitor `
  --enable-auto-upgrade true

### Resize Command (after metrics baseline)
az vm resize --resource-group rg-sre-demo-workloads --name vm-nozone-staging --size Standard_D2s_v5
```

---

## Verification Steps

1. ✅ Confirm AMA is NOT installed on `vm-nozone-staging`
2. ✅ Confirm memory metrics are unavailable via Azure Monitor query
3. ✅ Run the compute subagent against the demo subscription
4. ✅ Verify the subagent detects the missing memory metrics
5. ✅ Verify the FitScore is reduced by 0.5 (e.g., 4.5 instead of 5.0)
6. ✅ Verify the output includes a data quality warning
7. ✅ Verify the output recommends installing AMA before resizing
8. ✅ Verify the output includes the AMA installation command

---

## Contrast: Same Subscription VMs With AMA Installed

| VM | AMA Installed | Memory Data | FitScore | Data Quality |
|---|---|---|---|---|
| `vm-oversized-v3` | Yes | Available | 5.0 | Full |
| `vm-devtest-nospotv5` | Yes | Available | 5.0 | Full |
| `vm-nozone-staging` | No | Missing | 4.5 | Degraded |

---

## Cleanup

Resources are managed by the demo environment. To clean up everything:

```powershell
az group delete --name rg-sre-demo-workloads --yes --no-wait
```
