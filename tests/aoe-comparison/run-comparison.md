# AOE vs SRE Agent Comparison Test Guide

This guide walks through deploying both the Azure Optimization Engine (AOE) and the SRE Agent compute optimization subagent against the same test subscription, then comparing their output side by side.

---

## Purpose

Validate that the SRE Agent subagents produce equivalent or superior recommendations compared to AOE. This comparison establishes:

1. **Parity** — the SRE Agent finds everything AOE finds
2. **Accuracy** — FitScores and savings estimates are consistent
3. **Enhancements** — new capabilities (FitScore, alternative SKU search, data gap detection) add value beyond AOE

---

## Prerequisites

- Test subscription set up per [test-subscription-setup.md](../test-subscription-setup.md)
- AOE deployed (see Step 1 below)
- SRE Agent configured with compute optimization subagent
- Access to both AOE workbook output and SRE Agent output

---

## Step 1: Deploy AOE to Test Subscription

Follow the official AOE deployment guide:

```bash
# Clone AOE repository
git clone https://github.com/helderpinto/AzureOptimizationEngine.git
cd AzureOptimizationEngine

# Deploy AOE (follow the README for full instructions)
# This will create:
#   - Automation Account with runbooks
#   - Log Analytics workspace
#   - Storage Account
#   - SQL Database (optional)
```

1. Deploy AOE to the test subscription
2. Wait for all 13 runbooks to complete at least one cycle (typically 24 hours)
3. Open the AOE Power BI / Workbook to view recommendations

---

## Step 2: Run AOE and Collect Results

After AOE has completed at least one data collection cycle:

1. Open the AOE workbook/dashboard
2. Filter to the test resource group (`rg-sre-agent-test`)
3. Export or screenshot all recommendations, noting:
   - Resource name
   - Recommendation type (right-size, deallocate, delete, etc.)
   - Recommended action / target SKU
   - FitScore (if available — AOE uses a FitScore model)
   - Estimated savings

---

## Step 3: Run SRE Agent Compute Subagent

Trigger the SRE Agent compute optimization subagent on the same test subscription:

1. Ensure the SRE Agent is configured with the test subscription scope
2. Trigger the compute subagent manually or wait for the scheduled run
3. Collect the output, which should include:
   - Resource name and ID
   - Recommendation type
   - Target SKU
   - FitScore with breakdown
   - Estimated monthly savings
   - Data quality notes

---

## Step 4: Compare Results Side by Side

Use the [comparison-results.md](comparison-results.md) template to document findings.

### What to Compare

| Dimension | What to Check |
|---|---|
| **Coverage** | Did both tools find the same resources? |
| **Recommendation Type** | Same action (right-size, deallocate, delete)? |
| **Target SKU** | Same recommended SKU? |
| **FitScore** | Scores within ±0.5 of each other? |
| **Savings Estimate** | Estimates within ±10% of each other? |
| **Data Quality** | Did SRE Agent flag missing metrics that AOE missed? |
| **Hard Constraints** | Did both tools catch disk/NIC violations? |

---

## Expected Differences

The SRE Agent is designed to match and exceed AOE. Expect the following differences:

### SRE Agent Should Match AOE On:
- Identifying oversized VMs via Advisor recommendations
- Detecting deallocated VMs (30+ days)
- Finding unattached disks
- Detecting orphaned network resources

### SRE Agent Should Improve Over AOE On:

| Area | AOE Behavior | SRE Agent Behavior |
|---|---|---|
| **FitScore granularity** | Basic fit scoring | 5-point scale with soft/hard constraint breakdown |
| **Alternative SKU search** | No alternative search | Searches same family for valid alternatives when primary fails |
| **Missing metrics detection** | May not flag gaps | Explicitly flags missing VM Insights and adjusts FitScore |
| **Real-time data** | Batch (daily/weekly) | Can query live metrics via Azure Monitor tools |
| **Stopped-not-deallocated** | May detect | Explicitly detects and recommends deallocation |
| **Output format** | Workbook / Power BI | Structured markdown with actionable CLI commands |

### Acceptable Discrepancies:
- Minor FitScore differences (±0.5) due to timing of metric collection
- AOE may surface recommendations SRE Agent doesn't if AOE has more historical data
- SRE Agent may flag items AOE doesn't (e.g., missing metrics)

---

## Step 5: Evaluate Parity

### Parity Criteria

The SRE Agent achieves **parity** with AOE when:

1. ✅ All resources flagged by AOE are also flagged by SRE Agent
2. ✅ Recommendation types match (right-size, deallocate, delete)
3. ✅ FitScores are within ±0.5
4. ✅ Savings estimates are within ±10%
5. ✅ No false negatives (resources AOE catches but SRE Agent misses)

### Beyond Parity

The SRE Agent demonstrates **improvement** over AOE when:

1. 🚀 It finds issues AOE misses (e.g., stopped-not-deallocated, missing metrics)
2. 🚀 It provides alternative SKU suggestions when the primary recommendation fails
3. 🚀 It provides richer context (FitScore breakdown, CLI commands, data quality notes)
4. 🚀 It operates in near-real-time instead of batch

---

## Troubleshooting

| Issue | Resolution |
|---|---|
| AOE shows no recommendations | Wait 24–48 hours for full data collection cycle |
| SRE Agent misses a resource | Check subscription scope and RBAC permissions |
| FitScore differs significantly | Compare metric collection time windows |
| Savings estimates differ | Check if pricing data sources differ (retail API vs EA pricing) |
