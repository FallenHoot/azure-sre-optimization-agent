# Compute Optimization Specialist

The Compute Optimization subagent is responsible for analyzing Azure compute resources (Virtual Machines) and generating right-sizing, deallocation, and deletion recommendations with validated FitScores.

---

## What It Does

1. **VM Right-Sizing** — Retrieves Azure Advisor cost recommendations for VMs, validates each recommendation using the FitScore methodology, and provides safe resize recommendations.
2. **Deallocated VM Detection** — Identifies VMs that have been deallocated for 30+ days and recommends deletion with savings estimates.
3. **Stopped-Not-Deallocated Detection** — Finds VMs stopped at the OS level but not deallocated in Azure (still incurring compute charges).
4. **Missing Metrics Detection** — Flags VMs without Azure Monitor Agent (AMA) and adjusts FitScore for incomplete data.
5. **Alternative SKU Search** — When Advisor's recommended SKU fails FitScore validation (hard constraint), searches the same VM family for a valid alternative.

---

## AOE Runbooks Replaced

This subagent replaces the following Azure Optimization Engine (AOE) runbooks:

| AOE Runbook | Coverage | Enhancement |
|---|---|---|
| Advisor Cost Recommendations | ✅ Full | Enhanced with FitScore validation |
| VM Right-Sizing | ✅ Full | Enhanced with alternative SKU search |
| VM Deallocated (Long-Running) | ✅ Full | Uses Activity Log queries |
| _(New: not in AOE)_ | Stopped-not-deallocated detection | New capability |
| _(New: not in AOE)_ | Missing metrics detection | New capability |

> **Attribution:** Derived from Azure Optimization Engine (AOE) by Hélder Pinto. Original: https://github.com/helderpinto/AzureOptimizationEngine

---

## FitScore Overview

The FitScore is a 1–5 scale that validates whether Advisor's recommended SKU is safe for the workload:

| Score | Meaning | Action |
|---|---|---|
| 5.0 | Perfect fit | Safe to resize |
| 4.0–4.9 | Good fit (minor warnings) | Resize with monitoring |
| 3.0–3.9 | Marginal fit | Review before resizing |
| 2.0–2.9 | Poor fit | Not recommended |
| 1.0 | Hard constraint violation | **Blocked** — search for alternative |

### Hard Constraints (Score = 1.0)
- Data disk count exceeds target SKU maximum
- NIC count exceeds target SKU maximum

### Soft Constraints (-0.5 per violation)
- P99 CPU > 80% of target vCPU capacity
- P99 Memory > 80% of target memory
- P99 IOPS > 80% of target max uncached IOPS
- P99 MiBps > 80% of target max uncached throughput
- P99 Network > 80% of target max network bandwidth

### Data Quality (-0.5)
- Missing memory metrics (no AMA/VM Insights)

For full details, see [knowledge-base/FitScore-Methodology.md](../../knowledge-base/FitScore-Methodology.md).

---

## How to Deploy

### 1. Ensure RBAC Is Configured

The subagent's Managed Identity needs these roles on target subscriptions:

- Reader
- Monitoring Reader
- Advisor Reader
- Log Analytics Reader

See [scripts/setup-rbac.sh](../../scripts/setup-rbac.sh).

### 2. Upload Knowledge Base

The compute subagent depends on these knowledge base documents:

- [FitScore-Methodology.md](../../knowledge-base/FitScore-Methodology.md)
- [Threshold-Defaults.md](../../knowledge-base/Threshold-Defaults.md)
- [SKU-Constraint-Rules.md](../../knowledge-base/SKU-Constraint-Rules.md)
- [Resource-Graph-Queries.md](../../knowledge-base/Resource-Graph-Queries.md)
- [Metric-Collection-Guide.md](../../knowledge-base/Metric-Collection-Guide.md)
- [Savings-Estimation.md](../../knowledge-base/Savings-Estimation.md)
- [Recommendation-Format.md](../../knowledge-base/Recommendation-Format.md)
- [Severity-Classification.md](../../knowledge-base/Severity-Classification.md)
- [Workload-Patterns.md](../../knowledge-base/Workload-Patterns.md)

### 3. Deploy the Subagent

```bash
# az sre-agent subagent create \
#   --resource-group $AGENT_RG \
#   --agent-name $AGENT_NAME \
#   --config "subagents/compute-optimization/agent.yaml"
```

### 4. Configure the Schedule

```bash
# az sre-agent schedule create \
#   --resource-group $AGENT_RG \
#   --agent-name $AGENT_NAME \
#   --subagent compute-optimization \
#   --config "subagents/compute-optimization/schedule.yaml"
```

Default schedule: **Daily at 06:00 UTC**

---

## Files in This Directory

| File | Purpose |
|---|---|
| [agent.yaml](agent.yaml) | Subagent configuration (tools, knowledge base, instructions) |
| [schedule.yaml](schedule.yaml) | Schedule configuration (cron expression, timezone) |
| [README.md](README.md) | This file |

---

## Testing

See the following test scenarios:

- [tests/scenarios/oversized-vm.md](../../tests/scenarios/oversized-vm.md) — Oversized VM with low utilization
- [tests/scenarios/hard-constraint.md](../../tests/scenarios/hard-constraint.md) — Hard constraint violation (disk count)
- [tests/scenarios/deallocated-vm.md](../../tests/scenarios/deallocated-vm.md) — VM deallocated 30+ days
- [tests/scenarios/missing-metrics.md](../../tests/scenarios/missing-metrics.md) — VM without Azure Monitor Agent
- [tests/scenarios/alternative-sku.md](../../tests/scenarios/alternative-sku.md) — Alternative SKU search
- [tests/fitscore-test-cases.md](../../tests/fitscore-test-cases.md) — FitScore calculation test cases

---

## Related Documentation

- [Architecture Decisions](../../docs/architecture.md)
- [AOE Feature Comparison](../../docs/aoe-comparison.md)
- [Configuration Guide](../../docs/configuration.md)
- [Deployment Guide](../../docs/deployment-guide.md)
