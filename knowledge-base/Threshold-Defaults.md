# Threshold Defaults

## Purpose

This document defines the default thresholds for all metrics used across the Azure SRE Agent Optimization Engine subagents. These thresholds determine when a resource is considered underutilized, idle, or misconfigured, and drive the generation of optimization recommendations.

Most compute thresholds are derived directly from the [Azure Optimization Engine (AOE) by Hélder Pinto](https://github.com/helderpinto/AzureOptimizationEngine). Where new thresholds have been introduced for this project, they are marked as **New**.

---

## Metric Lookback & Aggregation Defaults

| Setting | Default | Configurable Values | Notes |
|---|---|---|---|
| Lookback Period | 7 days | 7, 30, 90 days | Longer periods reduce false positives but increase query cost |
| Time Grain | 1 hour (PT1H) | PT1H only | Finer grains increase cost and are rarely needed |
| Aggregation | P99 (99th percentile) | P95, P99, Max | P99 captures near-peak without single-spike sensitivity |

---

## Compute Thresholds

| Metric | Default Threshold | Unit | Direction | Source | Rationale |
|---|---|---|---|---|---|
| CPU Utilization | 30% | P99 over lookback | Below → underutilized | AOE | If the 99th percentile CPU is below 30%, the VM is consistently idle and a candidate for rightsizing or deallocation. |
| Memory Utilization | 50% | P99 over lookback | Below → underutilized | AOE | Memory below 50% at P99 indicates significant over-provisioning. |
| Network Throughput | 750 Mbps | P99 over lookback | Below → overprovisioned NIC/SKU | AOE | If peak network throughput never approaches 750 Mbps, a smaller SKU with less network bandwidth may suffice. |
| Disk IOPS | N/A (compared against SKU capability) | Ratio of actual vs SKU max | Below ratio → overprovisioned disk | AOE | No fixed threshold; instead, actual IOPS are compared to the SKU's published max IOPS. A ratio below 30% suggests over-provisioning. |
| Disk Throughput | N/A (compared against SKU capability) | Ratio of actual vs SKU max | Below ratio → overprovisioned disk | AOE | Same approach as IOPS — compare actual throughput against disk tier capability. |
| Deallocated VM Age | 30 days | Days since last deallocation | Above → recommend deletion | AOE | VMs deallocated for more than 30 days are unlikely to be needed and still incur disk costs. |

---

## Storage Thresholds

| Metric | Default Threshold | Unit | Direction | Source | Rationale |
|---|---|---|---|---|---|
| Snapshot Age | 90 days | Days since creation | Above → recommend deletion | New | Snapshots older than 90 days are rarely needed and accumulate cost. |
| Storage Account Last Access (Hot Tier) | 30 days | Days since last read/write | Above → recommend tier change | New | Hot-tier storage not accessed for 30 days should be moved to Cool or Archive. |
| Unattached Managed Disk Age | 7 days | Days since detachment | Above → recommend deletion | AOE | Unattached disks older than 7 days are likely orphaned. |

---

## Network Thresholds

| Metric | Default Threshold | Unit | Direction | Source | Rationale |
|---|---|---|---|---|---|
| Load Balancer Backend Pool Count | 0 | Count | Equal to 0 → unused | AOE | A load balancer with zero backend pool members is unused and billable. |
| Application Gateway Backend Target Count | 0 | Count | Equal to 0 → unused | AOE | An App Gateway with no backend targets is unused and billable. |
| Public IP Association | Unassociated | Boolean | Unassociated → unused | AOE | Unassociated public IPs incur charges. |
| NSG Rule Count (custom) | 0 | Count | Equal to 0 → default only | New | NSGs with only default rules may be unnecessary. |

---

## PaaS Thresholds

| Metric | Default Threshold | Unit | Direction | Source | Rationale |
|---|---|---|---|---|---|
| App Service Plan App Count | 0 | Count | Equal to 0 → unused | AOE | Empty App Service Plans still bill. |
| App Service CPU | 30% | P99 over lookback | Below → overprovisioned | New | Similar logic to VM CPU thresholds. |
| App Service Memory | 50% | P99 over lookback | Below → overprovisioned | New | Similar logic to VM memory thresholds. |
| SQL DB DTU/CPU Utilization | 30% | P99 over lookback | Below → overprovisioned | New | SQL databases consistently under 30% DTU usage can be downsized. |

---

## Governance & Compliance Thresholds

| Metric | Default Threshold | Unit | Direction | Source | Rationale |
|---|---|---|---|---|---|
| App Credential Expiry Warning | 30 days | Days until expiry | Below → warn | New | Credentials expiring within 30 days need rotation planning. |
| App Credential Expired | 0 days | Days past expiry | Past expiry → critical | New | Expired credentials are a security risk. |
| Outdated API Version Age | 365 days | Days since API version GA | Above → recommend update | New | API versions more than 1 year old may lack security patches. |

---

## Tag-Based Override System

Thresholds can be overridden at multiple scopes using Azure resource tags. Overrides are evaluated in order of specificity:

1. **Resource-level tag** (highest priority)
2. **Resource-group-level tag**
3. **Subscription-level tag**
4. **Default value** (lowest priority)

### Tag Format

Tags use the prefix `aoe:` followed by the threshold name in camelCase:

| Tag Name | Example Value | Effect |
|---|---|---|
| `aoe:cpuThreshold` | `40` | Override CPU threshold to 40% for this resource |
| `aoe:memoryThreshold` | `60` | Override memory threshold to 60% |
| `aoe:networkThreshold` | `500` | Override network threshold to 500 Mbps |
| `aoe:lookbackDays` | `30` | Use 30-day lookback instead of 7 |
| `aoe:snapshotAgeDays` | `180` | Allow snapshots up to 180 days before flagging |
| `aoe:deallocatedVmDays` | `60` | Allow VMs to be deallocated for 60 days |
| `aoe:exclude` | `true` | Exclude this resource from all optimization scans |

### Override Resolution Example

```
Resource tag aoe:cpuThreshold = 40
Resource Group tag aoe:cpuThreshold = 35
Subscription tag aoe:cpuThreshold = 25
Default = 30

→ Effective threshold for this resource: 40 (resource-level wins)
```

### Exclusion Tag

Setting `aoe:exclude` to `true` at any scope will exclude all resources in that scope from scanning. This is useful for:
- Development/test resources that are intentionally oversized
- Resources with known burst patterns not yet tagged
- Resources under active migration

---

## Threshold Validation Rules

When processing overrides, apply these validation rules:

| Threshold | Min Allowed | Max Allowed | Type |
|---|---|---|---|
| CPU % | 5 | 95 | Integer |
| Memory % | 5 | 95 | Integer |
| Network Mbps | 50 | 10000 | Integer |
| Lookback Days | 1 | 90 | Integer |
| Snapshot Age Days | 1 | 365 | Integer |
| Deallocated VM Days | 1 | 365 | Integer |
| Credential Expiry Days | 1 | 90 | Integer |

Invalid tag values should be logged as warnings and the default threshold used instead.

---

## Complete Threshold Reference Table

| # | Threshold Name | Default | Unit | Source | Category | Rationale |
|---|---|---|---|---|---|---|
| 1 | CPU Utilization | 30% | P99 | AOE | Compute | Near-peak CPU consistently low indicates over-provisioning |
| 2 | Memory Utilization | 50% | P99 | AOE | Compute | Memory at P99 below 50% means significant waste |
| 3 | Network Throughput | 750 Mbps | P99 | AOE | Compute/Network | Peak throughput well below NIC limits |
| 4 | Disk IOPS | vs SKU max | Ratio | AOE | Compute/Storage | Compare actual to provisioned capability |
| 5 | Disk Throughput | vs SKU max | Ratio | AOE | Compute/Storage | Compare actual to provisioned capability |
| 6 | Deallocated VM Age | 30 days | Days | AOE | Compute | Long-idle VMs should be deleted |
| 7 | Snapshot Age | 90 days | Days | New | Storage | Old snapshots accumulate cost |
| 8 | Storage Last Access | 30 days | Days | New | Storage | Idle hot-tier data should be tiered down |
| 9 | Unattached Disk Age | 7 days | Days | AOE | Storage | Orphaned disks cost money |
| 10 | LB Backend Pool Count | 0 | Count | AOE | Network | Zero backends = unused LB |
| 11 | AppGW Backend Target Count | 0 | Count | AOE | Network | Zero targets = unused AppGW |
| 12 | Public IP Association | Unassociated | Boolean | AOE | Network | Unassociated IPs cost money |
| 13 | App Service Plan App Count | 0 | Count | AOE | PaaS | Empty plans still bill |
| 14 | App Service CPU | 30% | P99 | New | PaaS | Same logic as VM CPU |
| 15 | App Service Memory | 50% | P99 | New | PaaS | Same logic as VM memory |
| 16 | SQL DB DTU/CPU | 30% | P99 | New | PaaS | Underutilized SQL can be downsized |
| 17 | Credential Expiry Warning | 30 days | Days | New | Governance | Approaching expiry needs attention |
| 18 | Outdated API Version | 365 days | Days | New | Governance | Old API versions may lack patches |
