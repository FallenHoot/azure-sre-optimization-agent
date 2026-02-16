# FitScore Test Cases

This document defines test cases for validating the FitScore calculation logic. Each test case specifies a current SKU, a target (recommended) SKU, current workload metrics, and the expected FitScore result.

## FitScore Scoring Reference

| Score | Meaning |
|---|---|
| 5.0 | Perfect fit — all metrics well within target SKU capabilities |
| 4.0–4.9 | Good fit — minor soft constraint warnings |
| 3.0–3.9 | Marginal fit — multiple soft constraint concerns |
| 2.0–2.9 | Poor fit — significant risk of performance degradation |
| 1.0 | Hard constraint violation — recommendation is invalid |

### Scoring Rules

- **Hard constraints** (disk count, NIC count exceed target max): Score = **1.0** immediately
- **Soft constraint violations** (P99 metric > 80% of target capacity): Score reduced by **-0.5** per violation
- **Missing metrics** (e.g., no memory data from VM Insights): Score reduced by **-0.5**
- **Base score** starts at **5.0**

---

## Test Cases

| # | Test Name | Current SKU | Target SKU | Data Disks | NICs | P99 CPU (%) | P99 Memory (%) | P99 IOPS | P99 MiBps | P99 Network (Mbps) | Expected FitScore | Expected Result |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Perfect Fit | Standard_D8s_v5 | Standard_D4s_v5 | 2 | 1 | 12% | 25% | 1,200 | 80 | 500 | **5.0** | All metrics well within D4s_v5 limits. Safe to resize. |
| 2 | CPU Threshold Exceeded | Standard_D8s_v5 | Standard_D4s_v5 | 2 | 1 | 85% | 25% | 1,200 | 80 | 500 | **4.5** | P99 CPU >80% of target vCPU capacity. Soft warning: CPU pressure risk. |
| 3 | Memory Threshold Exceeded | Standard_D8s_v5 | Standard_D4s_v5 | 2 | 1 | 12% | 88% | 1,200 | 80 | 500 | **4.5** | P99 memory >80% of target memory. Soft warning: memory pressure risk. |
| 4 | CPU + Memory Exceeded | Standard_D8s_v5 | Standard_D4s_v5 | 2 | 1 | 85% | 88% | 1,200 | 80 | 500 | **4.0** | Both CPU and memory soft constraints triggered. Two -0.5 penalties. |
| 5 | Disk IOPS Exceeded | Standard_D8s_v5 | Standard_D4s_v5 | 2 | 1 | 12% | 25% | 5,800 | 80 | 500 | **4.0** | P99 IOPS >80% of target max uncached IOPS. Additional -0.5 for IOPS + adjustment from base. |
| 6 | Hard Constraint: Disk Count | Standard_D8s_v5 | Standard_D2s_v5 | 7 | 1 | 12% | 25% | 1,200 | 80 | 500 | **1.0** | D2s_v5 max data disks = 4, VM has 7 attached. Hard constraint violation. |
| 7 | Hard Constraint: NIC Count | Standard_D8s_v5 | Standard_B2s | 1 | 4 | 12% | 25% | 1,200 | 80 | 500 | **1.0** | B2s max NICs = 2, VM has 4 attached. Hard constraint violation. |
| 8 | Missing Memory Metrics | Standard_D8s_v5 | Standard_D4s_v5 | 2 | 1 | 12% | N/A | 1,200 | 80 | 500 | **4.5** | No VM Insights / AMA installed. Memory data unavailable. -0.5 penalty for missing data. |
| 9 | Multiple Soft Violations | Standard_D8s_v5 | Standard_D2s_v5 | 3 | 1 | 82% | 85% | 3,000 | 150 | 4,500 | **3.0** | CPU, memory, IOPS, and network all exceed 80% of target. Four -0.5 penalties = -2.0. |
| 10 | All Soft Constraints Exceeded | Standard_D16s_v5 | Standard_D2s_v5 | 3 | 1 | 90% | 92% | 4,500 | 180 | 5,000 | **2.5** | All five soft constraints exceeded (CPU, memory, IOPS, MiBps, network). Five -0.5 penalties = -2.5. |

---

## Additional Edge Case Tests

| # | Test Name | Current SKU | Target SKU | Data Disks | NICs | P99 CPU (%) | P99 Memory (%) | P99 IOPS | P99 MiBps | P99 Network (Mbps) | Expected FitScore | Expected Result |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 11 | Hard + Soft Combined | Standard_D8s_v5 | Standard_D2s_v5 | 7 | 1 | 90% | 92% | 4,500 | 180 | 5,000 | **1.0** | Hard constraint (disk count) overrides all soft scores. |
| 12 | Boundary: Exactly 80% | Standard_D8s_v5 | Standard_D4s_v5 | 2 | 1 | 80% | 80% | — | — | — | **5.0** | Metrics at exactly 80% do NOT trigger soft penalty (threshold is >80%). |
| 13 | Boundary: Just Above 80% | Standard_D8s_v5 | Standard_D4s_v5 | 2 | 1 | 81% | 81% | — | — | — | **4.0** | Metrics at 81% trigger soft penalties. Two -0.5 = -1.0. |
| 14 | Same SKU (No Change) | Standard_D4s_v5 | Standard_D4s_v5 | 2 | 1 | 50% | 50% | — | — | — | **5.0** | No resize needed; current = target. Should not appear as recommendation. |
| 15 | Missing All Metrics | Standard_D8s_v5 | Standard_D4s_v5 | 2 | 1 | N/A | N/A | N/A | N/A | N/A | **4.5** | No metrics at all. Single -0.5 for data quality. Flag for manual review. |

---

## Validation Process

1. For each test case, calculate the FitScore using the FitScore methodology in [knowledge-base/FitScore-Methodology.md](../knowledge-base/FitScore-Methodology.md)
2. Verify the score matches the expected value
3. Verify the result description matches the expected behavior
4. Document any discrepancies and update either the test case or the methodology

## SKU Reference (for test validation)

| SKU | vCPUs | Memory (GiB) | Max Data Disks | Max NICs | Max Uncached IOPS | Max Uncached MiBps | Max Network (Mbps) |
|---|---|---|---|---|---|---|---|
| Standard_B2s | 2 | 4 | 4 | 2 | 3,200 | 48 | 800 |
| Standard_D2s_v5 | 2 | 8 | 4 | 2 | 3,750 | 85 | 12,500 |
| Standard_D4s_v5 | 4 | 16 | 8 | 2 | 6,400 | 145 | 12,500 |
| Standard_D8s_v5 | 8 | 32 | 16 | 4 | 12,800 | 290 | 12,500 |
| Standard_D16s_v5 | 16 | 64 | 32 | 8 | 25,600 | 580 | 12,500 |
