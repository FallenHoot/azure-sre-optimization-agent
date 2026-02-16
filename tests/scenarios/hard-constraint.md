# Test Scenario: Hard Constraint Violation

## Objective

Validate that the compute optimization subagent correctly identifies a hard constraint violation (data disk count exceeds target SKU maximum) and assigns a FitScore of 1.0, blocking the recommendation.

---

## Demo Resource

| Property | Value |
|---|---|
| **VM Name** | `vm-oversized-v3` |
| **Resource Group** | `rg-sre-demo-workloads` |
| **Region** | swedencentral |
| **Current SKU** | Standard_D8s_v3 (8 vCPU / 32 GiB) |
| **Data Disks** | 1× 256 GB Premium_LRS |
| **Tags** | `environment=production`, `workload=web-frontend` |
| **Deployed By** | [`infra/demo/modules/demo-resources.bicep`](../../infra/demo/modules/demo-resources.bicep) — module `vm1` |

> **Note:** The demo VM has only 1 data disk, so this scenario primarily tests the FitScore **logic** using the demo as a baseline. For a full hard-constraint violation test, additional disks can be attached manually (see below), or validate using `simulate_e2e.py` mock data which includes a VM with 7 disks.

---

## Option A: Logic-Only Test (Using Demo As-Is)

With 1 data disk, verify that the subagent's FitScore correctly checks disk count against the target SKU's `maxDataDiskCount`. Even with 1 disk, if Advisor recommends an extremely small SKU, this check matters.

### SKU Constraints Reference

| SKU | Max Data Disks | Max NICs |
|---|---|---|
| Standard_D8s_v3 (current) | 16 | 4 |
| Standard_D4s_v5 | 8 | 2 |
| Standard_D2s_v5 | 4 | 2 |
| Standard_B2s | 4 | 2 |

With only 1 disk attached, all targets pass → FitScore not blocked. This validates the **PASS path**.

---

## Option B: Attach Additional Disks for Full Test

To create a genuine hard-constraint violation, attach more data disks:

```powershell
# Attach 6 additional data disks (7 total with the existing one)
for ($i = 2; $i -le 7; $i++) {
    az vm disk attach `
        --resource-group rg-sre-demo-workloads `
        --vm-name vm-oversized-v3 `
        --name "vm1-datadisk-0$i" `
        --size-gb 32 `
        --sku Premium_LRS `
        --new
}
```

Now with 7 data disks, if Advisor recommends `Standard_D2s_v5` (max 4): **hard constraint violation** → FitScore 1.0.

---

## Option C: E2E Simulation (No Azure Required)

Use the mock E2E simulation which includes `vm-web-prod-02` with high disk count:

```powershell
python tests/simulate_e2e.py
```

---

## Expected Results (With 7 Disks — Option B)

### Scenario A: Advisor Recommends D2s_v5

| Check | Expected |
|---|---|
| Advisor recommendation | Right-size to Standard_D2s_v5 |
| Data disk check | 7 attached > 4 max → **HARD VIOLATION** |
| FitScore | **1.0** |
| Recommendation blocked | Yes — cannot safely resize |
| Alternative SKU search | Subagent should search D-series for alternatives |
| Alternative found | Standard_D4s_v5 (max 8 disks, 7 ≤ 8) |
| Alternative FitScore | ≥ 4.0 (if other metrics are within limits) |

### Expected FitScore Breakdown (D2s_v5 target)

```
Base Score:                    5.0
Hard Constraint — Disk Count:  FAIL (7 > 4)
─────────────────────────────────────
Final FitScore:                1.0  ❌ BLOCKED
Reason: VM has 7 data disks; Standard_D2s_v5 supports max 4.
```

### Scenario B: Advisor Recommends D4s_v5

| Check | Expected |
|---|---|
| Advisor recommendation | Right-size to Standard_D4s_v5 |
| Data disk check | 7 attached ≤ 8 max → PASS |
| FitScore | ≥ 4.0 (depending on metrics) |
| Recommendation | Proceed with resize |

---

## Expected Subagent Output (Scenario A — Blocked)

```markdown
## vm-oversized-v3 (Standard_D8s_v3)

### Advisor Recommendation: Standard_D2s_v5 — BLOCKED
- **FitScore:** 1.0 / 5.0 ❌
- **Reason:** Hard constraint violation — VM has 7 data disks, Standard_D2s_v5 supports max 4.
- **Action:** Do NOT resize to Standard_D2s_v5.

### Alternative Recommendation: Standard_D4s_v5
- **FitScore:** 4.5 / 5.0 ✅
- **Savings:** ~$140/month
- **Risk:** Low
- **Action:** Right-size to Standard_D4s_v5

#### Resize Command
az vm resize --resource-group rg-sre-demo-workloads --name vm-oversized-v3 --size Standard_D4s_v5
```

---

## Verification Steps

1. ✅ Confirm VM has expected number of data disks attached
2. ✅ Confirm Azure Advisor recommends a smaller SKU
3. ✅ Run the compute subagent against the demo subscription
4. ✅ If target SKU max disks < attached count: Verify FitScore = 1.0
5. ✅ Verify the subagent blocks the original recommendation
6. ✅ Verify the subagent searches for alternative SKUs
7. ✅ Verify the alternative SKU supports ≥ attached disk count
8. ✅ Verify the alternative recommendation has FitScore ≥ 4.0

---

## Cleanup

If extra disks were attached (Option B), detach them:

```powershell
for ($i = 2; $i -le 7; $i++) {
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
