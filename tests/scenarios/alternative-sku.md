# Test Scenario: Alternative SKU Search

## Objective

Validate that the compute optimization subagent finds and recommends an alternative SKU when Azure Advisor's primary suggestion fails FitScore validation due to a hard constraint (e.g., disk count), but a different SKU in the same family would pass.

---

## Demo Resource

| Property | Value |
|---|---|
| **VM Name** | `vm-oversized-v3` (with additional disks attached) |
| **Resource Group** | `rg-sre-demo-workloads` |
| **Region** | swedencentral |
| **Current SKU** | Standard_D8s_v3 (8 vCPU / 32 GiB) |
| **Tags** | `environment=production`, `workload=web-frontend` |
| **Deployed By** | [`infra/demo/modules/demo-resources.bicep`](../../infra/demo/modules/demo-resources.bicep) — module `vm1` |

> **Note:** The demo VM deploys with 1 data disk. Attach 4 more (5 total) to trigger this scenario where Advisor's primary recommendation fails but an alternative passes.

---

## Setup

1. Deploy the demo environment:

```powershell
cd infra/demo
.\deploy-demo.ps1
```

2. Attach additional data disks (5 total):

```powershell
for ($i = 2; $i -le 5; $i++) {
    az vm disk attach `
        --resource-group rg-sre-demo-workloads `
        --vm-name vm-oversized-v3 `
        --name "vm1-datadisk-0$i" `
        --size-gb 32 `
        --sku Premium_LRS `
        --new
}
```

3. Install Azure Monitor Agent:

```powershell
az vm extension set `
  --resource-group rg-sre-demo-workloads `
  --vm-name vm-oversized-v3 `
  --name AzureMonitorLinuxAgent `
  --publisher Microsoft.Azure.Monitor `
  --enable-auto-upgrade true
```

### Verify Configuration

```powershell
# Verify 5 data disks attached
az vm show `
  --resource-group rg-sre-demo-workloads `
  --name vm-oversized-v3 `
  --query "storageProfile.dataDisks | length(@)" `
  --output tsv
# Expected: 5
```

---

## SKU Constraints Reference

| SKU | vCPUs | Memory (GiB) | Max Data Disks | Max NICs | Monthly Cost (est.) |
|---|---|---|---|---|---|
| Standard_D8s_v3 (current) | 8 | 32 | 16 | 4 | ~$280 |
| Standard_D2s_v5 (Advisor target) | 2 | 8 | **4** | 2 | ~$70 |
| Standard_D4s_v5 (alternative) | 4 | 16 | **8** | 2 | ~$140 |

---

## Alternative SKU Search Logic

The subagent should follow this process:

```
1. Receive Advisor recommendation: D8s_v3 → D2s_v5
2. Calculate FitScore for D2s_v5:
   - Hard constraint check: 5 disks > 4 max → FAIL
   - FitScore = 1.0 (blocked)
3. Trigger alternative SKU search:
   a. Identify the VM family: Dsv5-series (cross-gen from v3)
   b. List all SKUs in the family smaller than current (D8s_v3):
      - D2s_v5 (max 4 disks) → already failed
      - D4s_v5 (max 8 disks) → candidate
   c. Calculate FitScore for D4s_v5:
      - Hard constraint check: 5 disks ≤ 8 max → PASS
      - Soft constraints: evaluate CPU, memory, IOPS, etc.
   d. If FitScore ≥ 4.0, recommend D4s_v5 as alternative
4. Output both the failed primary and the successful alternative
```

### Querying Available SKUs in the Same Family

```powershell
# List all Dsv5-series SKUs available in the region
az vm list-skus `
  --location swedencentral `
  --resource-type virtualMachines `
  --query "[?contains(name, 'Standard_D') && contains(name, 's_v5')].{Name:name, vCPUs:capabilities[?name=='vCPUs'].value | [0], MaxDataDisks:capabilities[?name=='MaxDataDiskCount'].value | [0]}" `
  --output table
```

---

## Expected Results

| Check | Expected |
|---|---|
| Advisor primary recommendation | Standard_D2s_v5 (or smaller) |
| Primary FitScore | 1.0 (hard constraint: 5 disks > 4 max) |
| Primary recommendation blocked | Yes |
| Alternative search triggered | Yes |
| Alternative SKU found | Standard_D4s_v5 |
| Alternative FitScore | ≥ 4.0 |
| Alternative savings | ~$140/month (D8s_v3 → D4s_v5) |

---

## Expected Subagent Output

```markdown
## vm-oversized-v3 (Standard_D8s_v3)

### ❌ Advisor Recommendation: Standard_D2s_v5 — BLOCKED
- **FitScore:** 1.0 / 5.0 ❌
- **Reason:** Hard constraint violation — VM has 5 data disks, Standard_D2s_v5 supports max 4.
- **Action:** Do NOT resize to Standard_D2s_v5.

### ✅ Alternative Recommendation: Standard_D4s_v5
- **FitScore:** 4.5 / 5.0 ✅
- **Savings:** ~$140/month
- **Risk:** Low
- **Hard Constraints:** PASS (5 disks ≤ 8 max, 1 NIC ≤ 2 max)
- **Soft Constraints:** All metrics within 80% of target capacity
- **Action:** Right-size to Standard_D4s_v5

#### FitScore Breakdown
| Check | Value | Target Limit | Status |
|---|---|---|---|
| Data Disks | 5 | 8 | ✅ PASS |
| NICs | 1 | 2 | ✅ PASS |
| P99 CPU | 12% | 80% | ✅ PASS |
| P99 Memory | 25% | 80% | ✅ PASS |
| P99 IOPS | 1,200 | 5,120 | ✅ PASS |

#### Resize Command
az vm resize --resource-group rg-sre-demo-workloads --name vm-oversized-v3 --size Standard_D4s_v5
```

---

## Verification Steps

1. ✅ Confirm VM has 5 data disks attached
2. ✅ Confirm Azure Advisor recommends a smaller SKU
3. ✅ Run the compute subagent against the demo subscription
4. ✅ Verify the subagent assigns FitScore 1.0 to the Advisor recommendation
5. ✅ Verify the subagent triggers an alternative SKU search
6. ✅ Verify the subagent finds `Standard_D4s_v5` as an alternative
7. ✅ Verify the alternative passes hard constraint checks (5 disks ≤ 8 max)
8. ✅ Verify the alternative FitScore is ≥ 4.0
9. ✅ Verify the output includes both the blocked primary and the successful alternative
10. ✅ Verify the output includes a resize CLI command for the alternative

---

## Key Differentiator

This scenario demonstrates a key advantage of the SRE Agent over AOE:

- **AOE:** Would report the Advisor recommendation (D2s_v5) without validating disk constraints, potentially leading to a failed resize.
- **SRE Agent:** Validates constraints, blocks the unsafe recommendation, and proactively finds a safe alternative that still saves money.

---

## Cleanup

Detach extra disks and restore demo state:

```powershell
for ($i = 2; $i -le 5; $i++) {
    az vm disk detach `
        --resource-group rg-sre-demo-workloads `
        --vm-name vm-oversized-v3 `
        --name "vm1-datadisk-0$i"
    az disk delete `
        --resource-group rg-sre-demo-workloads `
        --name "vm1-datadisk-0$i" `
        --yes
}
```

To clean up the entire environment:

```powershell
az group delete --name rg-sre-demo-workloads --yes --no-wait
```
