# FitScore Methodology

> **Source:** Azure Optimization Engine — `Recommend-AdvisorCostAugmentedToBlobStorage.ps1`
> **Author:** Hélder Pinto (@helderpinto)
> **Ported by:** @zaolinsk for Azure SRE Agent subagent
> **Version:** 1.1.0

---

## Source of Truth

**This document defines the SCORING ALGORITHM** — step order, deduction
amounts, hard vs soft constraint classification, and interpretation
thresholds. These are stable and rarely change.

However, the SPECIFIC VALUES used in scoring (SKU capabilities, IOPS
caps, throughput limits, pricing) MUST come from live Azure APIs:
- **SKU capabilities:** `az vm list-skus --location <loc> --size <sku>`
- **Disk properties:** Azure Resource Graph query on `microsoft.compute/disks`
- **Pricing:** Azure Retail Prices API
- **Metrics:** Azure Monitor / Log Analytics

For authoritative documentation on constraints and behavior:
- VM sizes: https://learn.microsoft.com/azure/virtual-machines/sizes/overview
- Managed disk types: https://learn.microsoft.com/azure/virtual-machines/disks-types
- Resource SKU API: https://learn.microsoft.com/rest/api/compute/resource-skus/list

**If the live API data contradicts any values in this file, TRUST THE
LIVE API.** This file defines HOW to score. The APIs provide WHAT to
score against.

---

## Overview

FitScore is a **0–5 validation score** for VM rightsizing recommendations. It ensures
that Azure Advisor's SKU change suggestions will not break workloads by violating
hardware constraints or exceeding observed performance envelopes.

A FitScore of **5** means the target SKU satisfies all hardware constraints and the VM's
observed metrics are well within the target SKU's capabilities. A FitScore of **1** means
a hard constraint violation — the resize **must not** proceed.

---

## When to Use FitScore

Apply FitScore validation to **every running VM** — not just those with Advisor
recommendations. There are two paths:

- **Path A — Advisor recommendation exists:** Use the Advisor-suggested target SKU
  as the FitScore candidate.
- **Path B — No Advisor recommendation:** Automatically search for candidate SKUs
  with fewer vCPUs in the same region. Run FitScore against the top 3 candidates.
  Present the best-fit option with savings.

Do NOT apply FitScore to shutdown/deletion recommendations — those are evaluated
differently (see idle VM detection).

---

## Inputs Required

| Input | Source | Required |
|---|---|---|
| Target SKU (Advisor rec OR auto-discovered) | Azure Advisor API / SKU search | ✅ Yes |
| VM's attached data disk count | Azure Resource Graph | ✅ Yes |
| VM's attached NIC count | Azure Resource Graph | ✅ Yes |
| Disk details (tier, provisioned IOPS, MBps per disk) | Azure Resource Graph (`microsoft.compute/disks`) | ✅ Yes |
| VM extensions (SqlIaaSAgent, AMA, etc.) | `az vm extension list` | ✅ Yes |
| Accelerated Networking enabled? | NIC properties | ✅ Yes |
| Target SKU capabilities (full set — see Step 2) | Compute Resource SKU API (`az vm list-skus`) | ✅ Yes |
| P99 CPU utilization (7 days) | Azure Monitor / Log Analytics `Perf` table | ✅ Yes |
| P99 Memory utilization (7 days) | Azure Monitor / Log Analytics `Perf` table | ⚠️ Preferred |
| P99 Disk IOPS — reads + writes (7 days) | Azure Monitor / Log Analytics `Perf` table | ⚠️ Preferred |
| P99 Disk throughput — MiB/s (7 days) | Azure Monitor / Log Analytics `Perf` table | ⚠️ Preferred |
| P99 Network throughput — Mbps (7 days) | Azure Monitor Metrics / Log Analytics | ⚠️ Preferred |
| VM name (for workload inference) | Azure Resource Graph | ✅ Yes |
| Temp disk usage (ephemeral OS, pagefile, tempdb) | VM config / inferred from workload | ⚠️ Preferred |

---

## Calculation Procedure

### Step 1: Initialize

```
fitScore = 5.0
```

### Step 2: Look up target SKU capabilities

Run:
```bash
az vm list-skus --location <vm-location> --size <targetSku> --output json
```

**IMPORTANT:** Always use this live API call to get capability values.
Do NOT hardcode or assume capability values from this document or any
static file. SKU capabilities change as Azure updates hardware.

For the full list of available capabilities and their meanings, see:
https://learn.microsoft.com/rest/api/compute/resource-skus/list

Extract these capabilities from the result:

| Capability Name | Variable | Unit | Hard? |
|---|---|---|---|
| `MaxDataDiskCount` | `targetMaxDataDiskCount` | Count | ✅ Hard |
| `MaxNetworkInterfaces` | `targetMaxNICCount` | Count | ✅ Hard |
| `PremiumIO` | `targetSupportsPremium` | True/False | ✅ Hard |
| `AcceleratedNetworkingEnabled` | `targetSupportsAccelNet` | True/False | ✅ Hard |
| `MaxResourceVolumeMB` | `targetTempDiskMB` | MB (0=none) | ✅ Hard |
| `UncachedDiskIOPS` | `targetUncachedDiskIOPS` | IOPS | Soft |
| `UncachedDiskBytesPerSecond` | `targetUncachedDiskBytesPerSecond` | Bytes/sec | Soft |
| `vCPUsAvailable` | `targetSkuvCPUs` | Count | Soft |
| `MemoryGB` | `targetMemoryGB` | GiB | Soft |
| `ExpectedNetworkBandwidthInMbps` | `targetNetBandwidthMbps` | Mbps | Soft |

**Important:** Convert `UncachedDiskBytesPerSecond` to MiB/s:
```
targetUncachedDiskMiBps = targetUncachedDiskBytesPerSecond / 1024 / 1024
```

### Step 3: Hard constraint checks

These are **blocking** constraints. Any failure sets FitScore = 1 and stops further checks.

#### 3a. Data Disk Count

```
IF targetMaxDataDiskCount > 0:
    IF currentDataDiskCount is known:
        IF currentDataDiskCount > targetMaxDataDiskCount:
            fitScore = 1   ← HARD STOP
            result: "FAIL: needs {currentDataDiskCount}, target max {targetMaxDataDiskCount}"
        ELSE:
            result: "PASS: {currentDataDiskCount} attached, target max {targetMaxDataDiskCount}"
    ELSE:
        fitScore -= 1
        result: "UNKNOWN: data disk count unavailable, target max {targetMaxDataDiskCount}"
ELSE:
    fitScore -= 1
    result: "UNKNOWN: target SKU disk count data unavailable"
```

#### 3b. NIC Count

```
IF targetMaxNICCount > 0:
    IF currentNICCount is known:
        IF currentNICCount > targetMaxNICCount:
            fitScore = 1   ← HARD STOP
            result: "FAIL: needs {currentNICCount}, target max {targetMaxNICCount}"
        ELSE:
            result: "PASS: {currentNICCount} attached, target max {targetMaxNICCount}"
    ELSE:
        fitScore -= 1
        result: "UNKNOWN: NIC count unavailable, target max {targetMaxNICCount}"
ELSE:
    fitScore -= 1
    result: "UNKNOWN: target SKU NIC data unavailable"
```

**⚠️ CRITICAL:** If fitScore == 1 after Step 3, STOP. Do not proceed to soft checks.
Report this as a hard constraint violation.

#### 3c. Premium Storage

```
IF any attached disk has tier == 'Premium_LRS':
    IF targetSupportsPremium == False:
        fitScore = 1   ← HARD STOP
        result: "FAIL: VM uses Premium disks but target SKU does not support PremiumIO"
    ELSE:
        result: "PASS: Premium Storage supported"
ELSE:
    result: "N/A: No Premium disks attached"
```

#### 3d. Accelerated Networking

```
IF currentVM.acceleratedNetworking == True:
    IF targetSupportsAccelNet == False:
        fitScore = 1   ← HARD STOP
        result: "FAIL: VM has AccelNet enabled but target SKU does not support it"
    ELSE:
        result: "PASS: Accelerated Networking supported"
ELSE:
    result: "N/A: AccelNet not currently enabled"
```

#### 3e. Temp Disk Dependency

```
IF currentVM uses temp disk (pagefile/swap on D:, SQL tempdb on D:,
   or ephemeral OS disk configured):
    IF targetTempDiskMB == 0:
        fitScore = 1   ← HARD STOP
        result: "FAIL: VM uses temp disk but target SKU has no temp disk"
    ELSE:
        result: "PASS: Temp disk available ({targetTempDiskMB} MB)"
ELSE:
    result: "N/A: No temp disk dependency detected"
```

**Temp disk detection heuristics:**
- `properties.storageProfile.osDisk.diffDiskSettings` present → ephemeral OS disk
- SqlIaaSAgent extension + inferred workload = SQL → likely tempdb on D:
- VM name contains "sql" → check for tempdb on D: assumption
- If unknown, note "Temp disk dependency could not be verified" (no score deduction)

#### 3f. Ultra SSD / Premium SSD v2 Disk Support

```
IF any data disk has tier == 'PremiumV2_LRS' or tier == 'UltraSSD_LRS':
    IF targetSupportsUltraSSD == False (UltraSSDAvailable != True):
        fitScore = 1   ← HARD STOP
        result: "FAIL: VM has Premium SSD v2 / Ultra Disk but target SKU
                 does not support UltraSSD"
    ELSE:
        result: "PASS: UltraSSD supported on target"
ELSE:
    result: "N/A: No Premium SSD v2 or Ultra Disk attached"
```

**Important reminders about Premium SSD v2 and Ultra Disk:**
- They are DATA DISK ONLY — cannot be used as OS disks
- Premium SSD v2 IOPS and throughput are configured independently
  of disk size (unlike Premium SSD v1 where IOPS scales with size)
- Both require the VM SKU to support `UltraSSDAvailable`
- Both have regional and availability zone restrictions
- For the latest constraints and supported configurations, reference:
  https://learn.microsoft.com/azure/virtual-machines/disks-types

### Step 4: Soft constraint checks (IOPS and throughput)

These deduct from the score but do not force a hard stop.

#### 4a. Uncached Disk IOPS

```
IF targetUncachedDiskIOPS > 0:
    IF observedP99IOPS is known:
        IF observedP99IOPS >= targetUncachedDiskIOPS:
            fitScore -= 1
            result: "FAIL: P99 IOPS {observedP99IOPS} >= target cap {targetUncachedDiskIOPS}"
        ELSE:
            result: "PASS: P99 IOPS {observedP99IOPS}, target cap {targetUncachedDiskIOPS}"
    ELSE:
        fitScore -= 0.5
        result: "UNKNOWN: IOPS metrics unavailable, target cap {targetUncachedDiskIOPS}"
ELSE:
    fitScore -= 1
    result: "UNKNOWN: target SKU IOPS data unavailable"
```

#### 4b. Uncached Disk Throughput (MiB/s)

```
IF targetUncachedDiskMiBps > 0:
    IF observedP99MiBps is known:
        IF observedP99MiBps >= targetUncachedDiskMiBps:
            fitScore -= 1
            result: "FAIL: P99 throughput {observedP99MiBps} MiBps >= target cap {targetUncachedDiskMiBps} MiBps"
        ELSE:
            result: "PASS: P99 throughput {observedP99MiBps} MiBps, target cap {targetUncachedDiskMiBps} MiBps"
    ELSE:
        fitScore -= 0.5
        result: "UNKNOWN: throughput metrics unavailable, target cap {targetUncachedDiskMiBps} MiBps"
ELSE:
    fitScore -= 1
    result: "UNKNOWN: target SKU throughput data unavailable"
```

### Step 5: Performance metric checks

#### 5a. CPU Utilization

```
IF observedP99CPU is known:
    IF observedP99CPU >= cpuThreshold (default: 30%):
        fitScore -= 0.5
        result: "WARN: P99 CPU {observedP99CPU}% >= threshold {cpuThreshold}%"
    ELSE:
        result: "PASS: P99 CPU {observedP99CPU}%, threshold {cpuThreshold}%"
ELSE:
    result: "UNKNOWN: CPU metrics unavailable"
    (no score adjustment — CPU metrics should always be available)
```

#### 5b. Memory Utilization

```
IF observedP99Memory is known:
    IF observedP99Memory >= memoryThreshold (default: 50%):
        fitScore -= 0.5
        result: "WARN: P99 Memory {observedP99Memory}% >= threshold {memoryThreshold}%"
    ELSE:
        result: "PASS: P99 Memory {observedP99Memory}%, threshold {memoryThreshold}%"
ELSE:
    fitScore -= 0.5
    result: "UNKNOWN: Memory metrics unavailable (no VM Insights/AMA)"
```

#### 5c. Network Throughput

```
IF observedP99NetworkMbps is known:
    IF targetNetBandwidthMbps is known:
        IF observedP99NetworkMbps >= 0.8 * targetNetBandwidthMbps:
            fitScore -= 0.5
            result: "WARN: P99 Network {observedP99NetworkMbps} Mbps >= 80% of target cap {targetNetBandwidthMbps} Mbps"
        ELSE:
            result: "PASS: P99 Network {observedP99NetworkMbps} Mbps, target cap {targetNetBandwidthMbps} Mbps"
    ELSE:
        IF observedP99NetworkMbps >= networkThreshold (default: 750 Mbps):
            fitScore -= 0.1
            result: "WARN: P99 Network {observedP99NetworkMbps} Mbps >= threshold {networkThreshold} Mbps"
        ELSE:
            result: "PASS: P99 Network {observedP99NetworkMbps} Mbps, threshold {networkThreshold} Mbps"
ELSE:
    fitScore -= 0.25
    result: "UNKNOWN: Network metrics unavailable"
```

#### 5d. Provisioned Disk IOPS vs SKU Cap (burst risk)

```
totalProvisionedIOPS = SUM(diskIOPSReadWrite) across all attached data disks
IF targetUncachedDiskIOPS > 0:
    IF totalProvisionedIOPS > targetUncachedDiskIOPS:
        fitScore -= 0.5
        result: "WARN: Total provisioned IOPS {totalProvisionedIOPS} exceeds target SKU cap {targetUncachedDiskIOPS} — burst saturation risk"
    ELSE:
        result: "PASS: Provisioned IOPS {totalProvisionedIOPS}, target cap {targetUncachedDiskIOPS}"
```

#### 5e. Workload-Aware Constraints

```
IF inferredWorkload == 'SQL' or 'Database':
    IF targetSkuvCPUs < 4:
        fitScore -= 0.5
        result: "WARN: SQL workload on {targetSkuvCPUs} vCPUs — database workloads are CPU-sensitive under load"
    IF targetMemoryGB < 8:
        fitScore -= 0.5
        result: "WARN: SQL workload with {targetMemoryGB} GB memory — SQL Server needs substantial memory for buffer pool"
IF inferredWorkload == 'Web' or 'Application':
    IF targetNetBandwidthMbps is known AND targetNetBandwidthMbps < 1000:
        fitScore -= 0.25
        result: "WARN: Web workload on SKU with {targetNetBandwidthMbps} Mbps network cap — may constrain under load"
IF inferredWorkload == 'Unknown':
    result: "NOTE: Workload type could not be inferred — manual review recommended"
```

### Step 6: Clamp score

```
fitScore = max(0.0, fitScore)
```

### Step 7: Interpret

| FitScore Range | Interpretation | Action |
|---|---|---|
| **5.0** | All constraints pass, all metrics well within limits | ✅ Safe to resize |
| **4.0 – 4.9** | Minor soft constraint proximity | ✅ Likely safe, review evidence |
| **3.0 – 3.9** | Multiple soft constraints near limits | ⚠️ Caution — review metrics before proceeding |
| **2.0 – 2.9** | Significant constraint pressure or data gaps | ❌ Risky — do not auto-resize |
| **1.0 – 1.9** | Hard constraint violation | 🛑 Do NOT resize |
| **0.0 – 0.9** | Multiple hard violations | 🛑 Do NOT resize |

### Step 8: Alternative SKU Search (NEW — beyond AOE)

If the Advisor-recommended SKU has FitScore ≤ 2, OR if no Advisor recommendation
exists for the VM:

1. Query all VM SKUs available in the same region (LIVE API — this is
   the source of truth for what SKUs exist and their capabilities):
   ```bash
   az vm list-skus --location <location> --resource-type virtualMachines --output json
   ```

2. Pre-filter candidates:
   - `vCPUsAvailable` < current SKU's vCPUs (ensures cost savings)
   - `MaxDataDiskCount` >= current attached disk count
   - `MaxNetworkInterfaces` >= current NIC count
   - `PremiumIO` == True IF current VM uses any Premium_LRS disks
   - `AcceleratedNetworkingEnabled` == True IF current VM has it enabled
   - `MaxResourceVolumeMB` > 0 IF current VM depends on temp disk
   - SKU is available (not restricted) in the region

3. Run FitScore Steps 3–7 against each candidate (including the new
   hard constraints: Premium, AccelNet, Temp Disk)

4. Select the candidate with the highest FitScore that still provides savings

5. Report: "Advisor suggested {advisorSku} (FitScore {score}), but
   {alternativeSku} is a better fit (FitScore {altScore}, savings {$X}/month)"
   — OR if no Advisor rec: "{alternativeSku} is the best downsize candidate
   (FitScore {altScore}, savings {$X}/month)"

### Step 9: Prefer Newer SKU Generations (NEW — beyond AOE)

After identifying candidates in Step 8, apply generation preference:

1. Parse the SKU family and generation from the name (e.g., `Standard_D4s_v3`
   → family=Ds, gen=v3)
2. If a newer-generation equivalent exists AND passes all FitScore checks,
   prefer it over the older generation
3. Generation priority: higher version number = better price-perf.
   ALWAYS verify actual pricing via the Retail Prices API rather than
   assuming a fixed percentage improvement.
4. **Temp disk caveat:** Check `MaxResourceVolumeMB` from the SKU API.
   Some newer-gen SKUs have no local temp disk. If the VM uses temp
   disk, choose a variant with temp disk. Verify via API, not by name.
5. **ARM64 caveat:** Check `CpuArchitectureType` capability. Only
   suggest ARM64 if OS is Linux + no x86-dependent extensions.
   Ref: https://learn.microsoft.com/azure/virtual-machines/arm-processor-overview
6. A same-vCPU newer-gen SKU is typically cheaper with better
   performance — confirm the exact price difference from the API.
   Ref: https://learn.microsoft.com/azure/virtual-machines/sizes/overview

---

## Metric Queries (KQL)

### CPU — P99 over 7 days

```kql
Perf
| where TimeGenerated > ago(7d)
| where _ResourceId =~ "<vm-resource-id>"
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| where InstanceName == "_Total"
| summarize P99_CPU = percentile(CounterValue, 99) by _ResourceId
```

### Memory — P99 over 7 days

```kql
Perf
| where TimeGenerated > ago(7d)
| where _ResourceId =~ "<vm-resource-id>"
| where ObjectName == "Memory" and CounterName == "% Used Memory"
| summarize P99_Memory = percentile(CounterValue, 99) by _ResourceId
```

**Note:** Memory metrics require VM Insights or Azure Monitor Agent (AMA).
If no results, the VM does not have these agents installed.

### Disk IOPS — P99 over 7 days

```kql
Perf
| where TimeGenerated > ago(7d)
| where _ResourceId =~ "<vm-resource-id>"
| where CounterName in ("Disk Reads/sec", "Disk Writes/sec")
| summarize P99_IOPS = percentile(CounterValue, 99) by CounterName, _ResourceId
| summarize MaxP99_ReadIOPS = maxif(P99_IOPS, CounterName == "Disk Reads/sec"),
            MaxP99_WriteIOPS = maxif(P99_IOPS, CounterName == "Disk Writes/sec")
            by _ResourceId
| extend TotalP99IOPS = MaxP99_ReadIOPS + MaxP99_WriteIOPS
```

### Disk Throughput — P99 over 7 days (MiB/s)

```kql
Perf
| where TimeGenerated > ago(7d)
| where _ResourceId =~ "<vm-resource-id>"
| where CounterName in ("Disk Read Bytes/sec", "Disk Write Bytes/sec")
| summarize P99_Throughput = percentile(CounterValue, 99) by CounterName, _ResourceId
| summarize MaxP99_ReadMiBps = maxif(P99_Throughput, CounterName == "Disk Read Bytes/sec") / 1024 / 1024,
            MaxP99_WriteMiBps = maxif(P99_Throughput, CounterName == "Disk Write Bytes/sec") / 1024 / 1024
            by _ResourceId
| extend TotalP99MiBps = MaxP99_ReadMiBps + MaxP99_WriteMiBps
```

### Network — P99 over 7 days (Mbps)

```kql
Perf
| where TimeGenerated > ago(7d)
| where _ResourceId =~ "<vm-resource-id>"
| where ObjectName == "Network" and CounterName == "Total Bytes Transmitted"
| summarize P99_NetworkBytesPerSec = percentile(CounterValue, 99) by _ResourceId
| extend P99_NetworkMbps = P99_NetworkBytesPerSec * 8 / 1000 / 1000
```

---

## Example FitScore Calculation

**Scenario:** Advisor recommends Standard_D8s_v5 → Standard_D4s_v5
**Inferred workload:** Unknown (VM name: "app-server-prod-01")
**Disk profile:** 2 data disks, both Premium_LRS, 5000 provisioned IOPS each
**Accelerated Networking:** Enabled
**Temp disk usage:** No ephemeral OS disk, no SQL extensions

| Step | Dimension | Current / Observed | Target Cap | Result | Score Impact |
|---|---|---|---|---|---|
| Init | — | — | — | — | 5.0 |
| 3a | Data Disks | 2 attached | Max 8 | PASS | 5.0 |
| 3b | NICs | 1 attached | Max 2 | PASS | 5.0 |
| 3c | Premium Storage | Yes (2 disks) | PremiumIO=True | PASS | 5.0 |
| 3d | Accelerated Net | Enabled | Supported=True | PASS | 5.0 |
| 3e | Temp Disk | Not dependent | Available (75 GB) | N/A | 5.0 |
| 4a | Disk IOPS | P99: 3,200 | 6,400 | PASS | 5.0 |
| 4b | Disk MiBps | P99: 45 | 96 | PASS | 5.0 |
| 5a | CPU | P99: 35% | Threshold 30% | WARN | 4.5 |
| 5b | Memory | P99: 42% | Threshold 50% | PASS | 4.5 |
| 5c | Network | P99: 120 Mbps | Cap: 12,500 Mbps | PASS | 4.5 |
| 5d | Provisioned IOPS | 10,000 (2×5000) | 6,400 | WARN | 4.0 |
| 5e | Workload-aware | Unknown | — | NOTE | 4.0 |

**Final FitScore: 4.0** — Likely safe but review provisioned IOPS. The total
provisioned disk IOPS (10,000) exceeds the target SKU's uncached cap (6,400),
meaning under burst the VM could hit the SKU IOPS ceiling even though steady-
state P99 is only 3,200. Consider Standard_D4s_v5 only if burst IOPS is
acceptable, or look at Standard_E4s_v5 (higher IOPS cap).

---

## Differences from AOE's Implementation

| Aspect | AOE | SRE Agent Subagent |
|---|---|---|
| Data freshness | 7-day batch (data may be up to 7 days stale) | Real-time API queries (live source of truth) |
| Alternative SKUs | Not supported — only validates Advisor's suggestion | Searches SKU catalog via live API for better fits |
| No Advisor rec | Skips VM entirely | Auto-discovers candidate SKUs from live SKU API |
| Hard constraints | Data disks + NICs only | Data disks, NICs, Premium Storage, Accelerated Networking, Temp Disk |
| Disk analysis | Aggregate IOPS only | Per-disk provisioned IOPS + observed P99 + burst risk detection |
| Network bandwidth | Not checked | Compares P99 throughput against SKU's ExpectedNetworkBandwidthInMbps (from live API) |
| Workload awareness | None | Infers workload from VM name, extensions, disk profile; applies workload-specific thresholds |
| Lookback period | Fixed 7 days | Configurable (7, 30, 90 days) |
| Pattern awareness | None — P99 only | AI can analyze time series shape |
| Metric source | Pre-exported to Log Analytics custom tables | Direct Azure Monitor API queries |
| Missing data handling | Deducts 0.5 | Deducts 0.5 + explains what agent to install |
| Confidence expression | Binary (score number) | Can express confidence with context |
| Knowledge freshness | Static files only | Live APIs > MS Learn docs > static KB files |

---

## Attribution

The FitScore methodology was created by **Hélder Pinto** (@helderpinto) as part of the
[Azure Optimization Engine](https://github.com/microsoft/finops-toolkit/tree/dev/src/optimization-engine)
in the [FinOps Toolkit](https://github.com/microsoft/finops-toolkit). This document
faithfully ports the algorithm from the PowerShell implementation in
`Recommend-AdvisorCostAugmentedToBlobStorage.ps1` with enhancements for the SRE Agent
platform.
