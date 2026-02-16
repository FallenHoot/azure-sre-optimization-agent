# SKU Constraint Rules

> **Source:** Azure Optimization Engine — FitScore validation logic
> **Reference:** Azure Compute Resource SKUs REST API
> **Version:** 1.1.0

---

## Source of Truth

**This document defines the WORKFLOW and SCORING LOGIC** — which constraints
to check, how to classify them (hard vs soft), and what score deductions to
apply. It does NOT define the specific IOPS caps, throughput limits, pricing,
or SKU family specifications.

For actual values, ALWAYS query live Azure APIs:
- **SKU capabilities:** `az vm list-skus --location <loc> --size <sku>`
- **Disk specs:** `az graph query` on `microsoft.compute/disks` resources
- **Pricing:** Azure Retail Prices API (`https://prices.azure.com/api/retail/prices`)

For authoritative documentation on constraints and behavior:
- VM sizes: https://learn.microsoft.com/azure/virtual-machines/sizes/overview
- Managed disk types: https://learn.microsoft.com/azure/virtual-machines/disks-types
- Spot VMs: https://learn.microsoft.com/azure/virtual-machines/spot-vms
- Accelerated Networking: https://learn.microsoft.com/azure/virtual-network/accelerated-networking-overview
- Resource SKU API: https://learn.microsoft.com/rest/api/compute/resource-skus/list

**If the live API data contradicts anything in this file, TRUST THE LIVE API.**

---

## Overview

When validating a VM rightsizing recommendation, the target SKU must be checked against
the VM's current hardware configuration. This document defines which SKU capabilities
to check, how to retrieve them, and how to classify violations.

---

## SKU Capability Lookup

### Azure CLI Command

```bash
az vm list-skus --location <location> --size <skuName> --output json
```

### REST API Equivalent

```
GET https://management.azure.com/subscriptions/{subscriptionId}/providers/Microsoft.Compute/skus?api-version=2021-07-01&$filter=location eq '{location}'
```

### Response Structure

```json
{
  "name": "Standard_D4s_v5",
  "resourceType": "virtualMachines",
  "tier": "Standard",
  "size": "D4s_v5",
  "family": "standardDSv5Family",
  "locations": ["eastus"],
  "capabilities": [
    { "name": "MaxDataDiskCount", "value": "8" },
    { "name": "MaxNetworkInterfaces", "value": "2" },
    { "name": "UncachedDiskIOPS", "value": "6400" },
    { "name": "UncachedDiskBytesPerSecond", "value": "100663296" },
    { "name": "vCPUsAvailable", "value": "4" },
    { "name": "MemoryGB", "value": "16" },
    { "name": "MaxWriteAcceleratorDisksAllowed", "value": "0" },
    { "name": "PremiumIO", "value": "True" },
    { "name": "AcceleratedNetworkingEnabled", "value": "True" },
    { "name": "RdmaEnabled", "value": "False" },
    { "name": "HyperVGenerations", "value": "V1,V2" },
    { "name": "CpuArchitectureType", "value": "x64" },
    { "name": "TrustedLaunchDisabled", "value": "False" }
  ],
  "restrictions": []
}
```

---

## Constraint Classification

### Hard Constraints (Blocking)

Hard constraint violations mean the resize **cannot physically proceed** without first
removing hardware. FitScore = 1 (immediate stop).

| Constraint | SKU Capability | Check | Severity |
|---|---|---|---|
| **Data Disk Count** | `MaxDataDiskCount` | Current attached disks > target max | 🛑 HARD — FitScore = 1 |
| **NIC Count** | `MaxNetworkInterfaces` | Current attached NICs > target max | 🛑 HARD — FitScore = 1 |
| **Premium Storage** | `PremiumIO` | VM uses Premium_LRS disk but target PremiumIO == False | 🛑 HARD — FitScore = 1 |
| **Accelerated Networking** | `AcceleratedNetworkingEnabled` | VM has AccelNet enabled but target doesn't support it | 🛑 HARD — FitScore = 1 |
| **Temp Disk** | `MaxResourceVolumeMB` | VM depends on temp disk but target has 0 MB (no temp disk) | 🛑 HARD — FitScore = 1 |
| **Ultra SSD / Premium SSD v2** | `UltraSSDAvailable` | VM has PremiumV2_LRS or UltraSSD_LRS disks but target doesn't support Ultra | 🛑 HARD — FitScore = 1 |

**Why these are hard:** Azure will physically reject the resize API call if you attempt
to resize a VM to a SKU that cannot support its current disk or NIC configuration. There
is no workaround other than detaching hardware first.

### Soft Constraints (Performance Risk)

Soft constraint violations mean the target SKU **can** handle the resize, but observed
workload metrics suggest the VM may experience performance degradation. FitScore is
reduced but not hard-stopped.

| Constraint | SKU Capability | Metric Source | Check | Deduction |
|---|---|---|---|---|
| **Uncached Disk IOPS** | `UncachedDiskIOPS` | `Perf` table — `Disk Reads/sec` + `Disk Writes/sec` | P99 IOPS ≥ target cap | -1.0 |
| **Uncached Disk Throughput** | `UncachedDiskBytesPerSecond` | `Perf` table — `Disk Read Bytes/sec` + `Disk Write Bytes/sec` | P99 MiB/s ≥ target cap (converted) | -1.0 |
| **Provisioned Disk IOPS** | `UncachedDiskIOPS` | Disk resource properties (`diskIOPSReadWrite`) | Sum of all disks' provisioned IOPS > target cap | -0.5 |
| **CPU Utilization** | N/A (metric-based) | `Perf` table — `% Processor Time` | P99 CPU ≥ threshold (default 30%) | -0.5 |
| **Memory Utilization** | N/A (metric-based) | `Perf` table — `% Used Memory` | P99 Memory ≥ threshold (default 50%) | -0.5 |
| **Network Bandwidth** | `ExpectedNetworkBandwidthInMbps` | `Perf` table or Azure Monitor Metrics | P99 throughput ≥ 80% of target SKU cap | -0.5 |
| **Workload: SQL vCPUs** | N/A | Inferred from name/extensions | SQL workload AND target vCPUs < 4 | -0.5 |
| **Workload: SQL Memory** | N/A | Inferred from name/extensions | SQL workload AND target MemoryGB < 8 | -0.5 |

### Data Availability Penalties

When metrics are unavailable, FitScore is penalized to reflect uncertainty:

| Missing Data | Penalty | Reason |
|---|---|---|
| Disk IOPS metrics unavailable | -0.5 | Cannot validate storage performance fit |
| Disk throughput metrics unavailable | -0.5 | Cannot validate storage throughput fit |
| Memory metrics unavailable | -0.5 | VM Insights / AMA not installed |
| SKU capability data unavailable (IOPS) | -1.0 | Cannot determine target cap at all |
| SKU capability data unavailable (NIC/disk count) | -1.0 | Cannot determine target cap at all |

---

## Additional SKU Capabilities

Beyond the core FitScore constraints, check these capabilities:

| Capability | Classification | Why It Matters |
|---|---|---|
| `PremiumIO` | 🛑 HARD (FitScore=1) | VM uses Premium_LRS disks; target must support |
| `AcceleratedNetworkingEnabled` | 🛑 HARD (FitScore=1) | VM has AccelNet enabled; target must support |
| `UltraSSDAvailable` | 🛑 HARD (FitScore=1) | VM uses Premium SSD v2 or Ultra Disk; target must support |
| `MaxResourceVolumeMB` | 🛑 HARD (FitScore=1) | VM depends on temp disk (0 = no temp disk on target) |
| `HyperVGenerations` | ⚠️ Warning | Gen1 vs Gen2 — some VMs can't switch |
| `CpuArchitectureType` | ⚠️ Warning | x64 vs Arm64 — different architecture |
| `TrustedLaunchDisabled` | ⚠️ Warning | Trusted Launch VMs need compatible SKUs |
| `EncryptionAtHostSupported` | ⚠️ Warning | Required if using host-level encryption |
| `EphemeralOSDiskSupported` | ⚠️ Warning | Required if using ephemeral OS disks |

---

## SKU Availability and Restrictions

The `restrictions` array in the SKU response indicates zone or subscription-level restrictions:

```json
{
  "restrictions": [
    {
      "type": "Zone",
      "values": ["eastus"],
      "restrictionInfo": {
        "locations": ["eastus"],
        "zones": ["3"]
      },
      "reasonCode": "NotAvailableForSubscription"
    }
  ]
}
```

**Rules:**
- If the target SKU has `reasonCode: "NotAvailableForSubscription"` → skip it
- If the target SKU is zone-restricted and the VM is in that zone → skip it
- Always verify the target SKU is available in the VM's region

---

## Common SKU Families Reference

For a complete and current list of VM SKU families, their use cases,
and specifications, query the live SKU API:
```bash
az vm list-skus --location <location> --resource-type virtualMachines \
  --query "[?restrictions[0]==null].{name:name, family:family}" -o json
```

And reference the authoritative MS Learn documentation:
https://learn.microsoft.com/azure/virtual-machines/sizes/overview

**General heuristics** (the family classification logic is stable):
- **Ds/Dds families** — General purpose (balanced CPU/memory)
- **Es/Eds families** — Memory optimized (high memory-to-CPU ratio)
- **Fs family** — Compute optimized (high CPU-to-memory ratio)
- **Ls family** — Storage optimized (high local NVMe throughput)
- **Ms family** — Memory intensive (very large memory)
- **NC/ND families** — GPU compute
- **Bs family** — Burstable (variable CPU with credits)
- **Dps/Eps families** — ARM64 variants (Linux only, best price-perf)

When suggesting alternatives, prefer staying in the same family unless
the workload profile suggests a different family would be more efficient.
Always verify current availability and capabilities via the SKU API.

## SKU Generation Preference

Newer VM generations deliver better performance per dollar on the same
hardware class. When multiple generations pass all FitScore constraints,
**always prefer the newest available generation.**

To determine available generations and compare pricing, ALWAYS use:
1. **SKU API** to list available generations in the target region:
   ```bash
   az vm list-skus --location <location> --resource-type virtualMachines \
     --query "[?restrictions[0]==null].{name:name, family:family}" -o json
   ```
   Parse the generation from the family name (e.g., `standardDSv5Family`
   → gen v5, `standardDSv6Family` → gen v6).

2. **Retail Prices API** to compare actual pricing between generations:
   ```bash
   az rest --url "https://prices.azure.com/api/retail/prices?\$filter=armSkuName eq '<sku>' and armRegionName eq '<location>' and priceType eq 'Consumption' and serviceName eq 'Virtual Machines'"
   ```

3. **MS Learn** for generation-specific capabilities and caveats:
   https://learn.microsoft.com/azure/virtual-machines/sizes/overview

### Generation Upgrade Rules

1. **Always suggest a newer-gen SKU as the primary candidate** when it
   passes all FitScore constraints.

2. **Check `MaxResourceVolumeMB`** from the SKU API — some newer-gen
   SKUs have no local temp disk. If the VM uses temp disk, choose a
   variant with temp disk (e.g., Dds instead of Ds). Verify via API.

3. **ARM64 SKUs** offer best price-perf but require workload
   compatibility. Check `CpuArchitectureType` capability. Only suggest
   if OS is Linux and no x86-dependent extensions are detected.
   Ref: https://learn.microsoft.com/azure/virtual-machines/arm-processor-overview

4. **Same vCPU newer-gen is cheaper** — verify the price difference
   from the Retail Prices API rather than assuming a percentage.

5. **HyperVGeneration compatibility:** newer SKUs may require Gen2
   VMs. Check `HyperVGenerations` capability from the SKU API.

## Managed Disk Tier Reference

For current disk tier specifications (IOPS caps, throughput limits,
pricing, size ranges, and regional availability), ALWAYS reference:
https://learn.microsoft.com/azure/virtual-machines/disks-types

Do NOT rely on hardcoded IOPS/throughput numbers — Azure updates disk
tier capabilities over time. Query actual disk properties from the API.

### Disk Tier Classification (stable logic)

- **Standard HDD** (Standard_LRS) — ✅ Can be OS disk. Dev/test,
  backups, cold data. Lowest cost, highest latency.
- **Standard SSD** (StandardSSD_LRS) — ✅ Can be OS disk. Light
  production, web servers.
- **Premium SSD** (Premium_LRS) — ✅ Can be OS disk. Production
  databases, transaction-heavy apps. Requires PremiumIO on VM SKU.
- **Premium SSD v2** (PremiumV2_LRS) — ❌ **CANNOT be OS disk.**
  Data disks only. IOPS and throughput independently configurable
  (unlike Premium SSD v1 where IOPS scales with disk size).
  Requires `UltraSSDAvailable` on VM SKU. No host caching.
- **Ultra Disk** (UltraSSD_LRS) — ❌ **CANNOT be OS disk.**
  Data disks only. Sub-millisecond latency, extreme IOPS.
  Requires `UltraSSDAvailable` on VM SKU. Zone-specific.

### Critical Disk Tier Constraints

- Premium SSD v2 and Ultra Disk as DATA DISK ONLY is an architectural
  constraint — verify current status at the MS Learn link above
- When downgrading Premium SSD → Standard SSD, verify the VM SKU
  doesn't require PremiumIO and that host caching settings are compatible
- Standard HDD should only be used for OS disks on non-production VMs
- For pricing comparisons, use the Retail Prices API — never hardcode
  per-GB prices

## Azure Spot VM Eligibility Rules

For current Spot VM capabilities, constraints, supported SKUs, and
regional availability, ALWAYS reference:
https://learn.microsoft.com/azure/virtual-machines/spot-vms

Do NOT rely on hardcoded constraint lists — Spot support evolves.
Query the live SKU API and check the MS Learn page for the latest.

### Workload Eligibility Classification (stable logic)

The workload classification heuristics are stable — the reasoning
about which workloads tolerate eviction doesn't change with Azure:

**NEVER eligible (hard exclusions):**
- SQL Server / any database workload (stateful, eviction = data loss)
- Domain Controllers, Active Directory, DNS (infrastructure-critical)
- Single-instance production VMs with SLA requirements (no Spot SLA)
- VMs in Availability Sets (Spot cannot join AS)

**Good fit:**
- VMSS with capacity ≥ 3 behind a load balancer (absorbs evictions)
- Dev/test/QA/staging VMs (interruption acceptable)
- Batch processing, rendering, CI build agents (ephemeral, retryable)
- Stateless web/app servers behind load balancer (redundant)
- ML training with checkpointing (can resume)

**Maybe (needs manual review):**
- Production VMs with unknown workload type
- Single VMs not behind a load balancer

### Spot VM Constraints

These constraints are architecturally stable but verify details on
MS Learn for the latest:
- **No SLA.** Azure can evict at any time.
- **30-second eviction notice** via Azure Metadata Service
- **Cannot join Availability Sets** — standalone VMs or VMSS only
- **Eviction policies:** `Deallocate` or `Delete`
- **Reserved Instances and Spot are mutually exclusive**
- For disk compatibility, SKU restrictions, and region availability,
  check the MS Learn Spot VMs page above.

### Spot Savings Calculation

ALWAYS use the Retail Prices API for current Spot pricing:
```
paygoPrice = Retail Prices API → filter priceType == 'Consumption'
spotPrice  = Retail Prices API → look for spot-specific entries
spotSavingsPercent = (1 - spotPrice / paygoPrice) × 100
monthlySavings = (paygoPrice - spotPrice) × 730
```

Never hardcode savings percentages ("60–90%") — actual savings vary
by SKU, region, and time. Present three savings tiers:
1. **Rightsizing only:** current SKU → target SKU at pay-as-you-go
2. **Spot only:** current SKU at Spot price
3. **Combined:** target SKU at Spot price (maximum savings)

---

## Attribution

SKU constraint validation logic derived from the Azure Optimization Engine's FitScore
implementation by Hélder Pinto (@helderpinto).
