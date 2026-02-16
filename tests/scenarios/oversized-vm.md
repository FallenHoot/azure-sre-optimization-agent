# Test Scenario: Oversized VM

## Objective

Validate that the compute optimization subagent correctly identifies an oversized VM with low utilization and recommends downsizing with a FitScore ≥ 4.

---

## Demo Resource

| Property | Value |
|---|---|
| **VM Name** | `vm-oversized-v3` |
| **Resource Group** | `rg-sre-demo-workloads` |
| **Region** | swedencentral |
| **Current SKU** | Standard_D8s_v3 (8 vCPU / 32 GiB) |
| **OS Disk** | 512 GB Premium_LRS (oversized) |
| **Data Disks** | 1× 256 GB Premium_LRS (deleteOption: Detach) |
| **Tags** | `environment=production`, `workload=web-frontend` |
| **Deployed By** | [`infra/demo/modules/demo-resources.bicep`](../../infra/demo/modules/demo-resources.bicep) — module `vm1` |

### Additional Finding Triggers

- **Generation upgrade:** v3 → v5/v6 recommendation (old-gen SKU)
- **Oversized OS disk:** 512 GB Premium for a low-utilization workload
- **Premium data disk on idle VM:** Cost waste on Premium_LRS

---

## Setup

Deploy the demo environment (all resources deploy together):

```powershell
cd infra/demo
.\deploy-demo.ps1
```

Then install Azure Monitor Agent for metrics collection:

```powershell
az vm extension set `
  --resource-group rg-sre-demo-workloads `
  --vm-name vm-oversized-v3 `
  --name AzureMonitorLinuxAgent `
  --publisher Microsoft.Azure.Monitor `
  --enable-auto-upgrade true
```

### Ensure Low Utilization

The VM should idle after creation. Do **not** run any significant workloads. Expected metrics after 24–48 hours:

| Metric | Expected Value |
|---|---|
| P99 CPU | < 15% |
| P99 Memory | < 30% |
| P99 IOPS | < 500 |
| P99 Network | < 100 Mbps |

### Wait for Advisor Recommendation

Azure Advisor typically takes 24–48 hours to generate a right-sizing recommendation.

```powershell
az advisor recommendation list `
  --resource-group rg-sre-demo-workloads `
  --category Cost `
  --query "[?contains(resourceMetadata.resourceId, 'vm-oversized-v3')]"
```

---

## Expected Results

| Check | Expected |
|---|---|
| Advisor recommendation exists | Yes — right-size to D4s_v3 or smaller (or cross-gen to D4s_v5) |
| Subagent detects the recommendation | Yes |
| FitScore | ≥ 4.0 (all metrics well within target limits) |
| Hard constraint violations | None (1 data disk, 1 NIC — well within limits) |
| Soft constraint violations | None (all P99 metrics < 80% of target) |
| Generation upgrade noted | Yes — v3 → v5 recommended |
| Estimated savings | ~$140–280/month depending on target SKU |
| Recommendation output | Includes target SKU, FitScore breakdown, savings estimate, and resize CLI command |

### Expected FitScore Breakdown

```
Base Score:                    5.0
Hard Constraints (Disk/NIC):   PASS (1 disk ≤ max, 1 NIC ≤ max)
CPU Check (12% vs 80%):        PASS — no penalty
Memory Check (25% vs 80%):     PASS — no penalty
IOPS Check (500 vs limit):     PASS — no penalty
MiBps Check:                   PASS — no penalty
Network Check:                 PASS — no penalty
─────────────────────────────────────
Final FitScore:                5.0
```

### Expected Recommendation Output

```markdown
## vm-oversized-v3 (Standard_D8s_v3 → Standard_D4s_v5)

- **FitScore:** 5.0 / 5.0 ✅
- **Savings:** ~$140/month
- **Risk:** Low
- **Action:** Right-size + generation upgrade (v3 → v5)

### Resize Command
az vm resize --resource-group rg-sre-demo-workloads --name vm-oversized-v3 --size Standard_D4s_v5
```

---

## Verification Steps

1. ✅ Confirm Azure Advisor has a recommendation for this VM
2. ✅ Run the compute subagent against the demo subscription
3. ✅ Verify the subagent output includes `vm-oversized-v3`
4. ✅ Verify the recommended target SKU is smaller (D4s_v5 or similar)
5. ✅ Verify the FitScore is ≥ 4.0
6. ✅ Verify generation upgrade (v3 → v5) is noted
7. ✅ Verify estimated savings are within ±10% of expected
8. ✅ Verify the output includes a resize CLI command

---

## Cleanup

Resources are managed by the demo environment. To clean up everything:

```powershell
az group delete --name rg-sre-demo-workloads --yes --no-wait
```
