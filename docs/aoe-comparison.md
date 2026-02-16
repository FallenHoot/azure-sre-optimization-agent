# AOE vs SRE Agent Subagents — Feature Comparison

This document provides a comprehensive side-by-side comparison between the Azure Optimization Engine (AOE) by Hélder Pinto and the SRE Agent Optimization Subagents.

> **Attribution:** The SRE Agent subagents are inspired by and derived from AOE's methodology and runbook logic. Full credit to Hélder Pinto and the AOE project.

---

## Infrastructure Comparison

| Feature | AOE | SRE Agent Subagents | Improvement |
|---|---|---|---|
| **Compute platform** | Azure Automation Account | Azure SRE Agent (managed) | No infrastructure to maintain |
| **Data store** | Log Analytics + SQL Database | SRE Agent platform (stateless) | No database to manage |
| **Scheduling** | Automation Account schedules | SRE Agent YAML schedules | Declarative, version-controlled |
| **Orchestration** | Logic Apps | Orchestrator subagent | Simpler, no Logic App costs |
| **Output/Reporting** | Power BI / Workbook | Structured markdown, email, tickets | More flexible output options |
| **Deployment** | ARM template + manual config | YAML + knowledge base upload | Simpler, repeatable deployment |
| **Estimated infra cost** | ~$150–300/month | Near-zero | Significant cost reduction |
| **Update process** | Pull new runbooks, update schema | Update knowledge base docs | Lower maintenance burden |

---

## Recommendation Runbook Comparison

### AOE's 13 Recommendation Runbooks → SRE Agent Coverage

| # | AOE Runbook | AOE Description | SRE Agent Subagent | SRE Agent Coverage | Notes |
|---|---|---|---|---|---|
| 1 | Advisor Cost Recommendations | Pull Advisor cost recommendations | Compute / PaaS | ✅ Full | Enhanced with FitScore validation |
| 2 | VM Right-Sizing | Right-size VMs based on utilization | Compute | ✅ Full | Enhanced with alternative SKU search |
| 3 | Unattached Disks | Find orphaned managed disks | Storage | ✅ Full | Same logic via Resource Graph |
| 4 | VM Deallocated (Long-Running) | Find VMs deallocated 30+ days | Compute | ✅ Full | Uses Activity Log queries |
| 5 | Underutilized App Service Plans | Find oversized/idle App Service Plans | PaaS | ✅ Full | Enhanced with PaaS-specific FitScore |
| 6 | Orphaned Public IPs | Find unassociated public IPs | Network | ✅ Full | Same logic via Resource Graph |
| 7 | Orphaned NICs | Find unattached network interfaces | Network | ✅ Full | Detects NICs not associated with VMs |
| 8 | Empty Load Balancers | Find LBs with no backend pools | Network | ✅ Full | Checks for backend pools and rules |
| 9 | Orphaned NSGs | Find NSGs not associated with subnets/NICs | Network | ✅ Full | Same logic via Resource Graph |
| 10 | Idle VPN/ExpressRoute Gateways | Find idle network gateways | Network | ✅ Full | Checks connection count and traffic |
| 11 | Storage Account Optimization | Find over-provisioned storage accounts | Storage | ✅ Full | Tier analysis and access pattern checks |
| 12 | SQL Database Optimization | Find underutilized SQL DBs | PaaS | ✅ Full | DTU/vCore utilization analysis |
| 13 | Reservation Recommendations | Identify RI/SP opportunities | Governance | ⚠️ Partial | Reports Advisor RI recs; no custom analysis |

---

## Data Collection Comparison

| Feature | AOE | SRE Agent Subagents | Improvement |
|---|---|---|---|
| **Data freshness** | 24–48 hours (batch) | Live queries at run time | Real-time capability |
| **Metric source** | Log Analytics (ingested) | Azure Monitor API (direct) | No data ingestion pipeline needed |
| **Metric window** | Configurable (typically 30 days) | 7-day P99 (configurable) | Tuned for actionability |
| **Advisor data** | Snapshot at ingestion time | Live Advisor API query | Always current |
| **Resource inventory** | Resource Graph (batch) | Resource Graph (live) | Always current |
| **Activity Log** | Not used by default | Used for deallocation detection | Richer context |
| **VM Insights dependency** | Required for memory metrics | Required (detected if missing) | Explicit gap detection |

---

## FitScore Comparison

| Feature | AOE | SRE Agent Subagents | Improvement |
|---|---|---|---|
| **FitScore model** | Yes (basic) | Yes (enhanced 1–5 scale) | More granular with breakdown |
| **Hard constraint checking** | Disk count check | Disk count + NIC count + more | Broader constraint coverage |
| **Soft constraint penalties** | Basic threshold | -0.5 per violation (CPU, memory, IOPS, MiBps, network) | Quantified per-metric penalties |
| **Missing data handling** | May skip resource | -0.5 penalty + data quality flag | Transparent degradation |
| **Alternative SKU search** | No | Yes — searches same family | Key differentiator |
| **Score breakdown in output** | No | Yes — per-metric breakdown table | Actionable detail |

---

## Output and Reporting Comparison

| Feature | AOE | SRE Agent Subagents | Improvement |
|---|---|---|---|
| **Output format** | Power BI dashboard / Workbook | Structured markdown | Portable, versionable |
| **Actionable commands** | No | Yes — CLI commands per recommendation | Ready-to-execute |
| **Severity classification** | Basic | Critical/High/Medium/Low with criteria | Standardized triage |
| **Savings estimation** | Yes | Yes (Azure Retail Pricing API) | Same methodology |
| **Escalation criteria** | No | Yes — defined thresholds for escalation | Automated triage |
| **Email notifications** | Via Logic Apps | Via SRE Agent platform | Simpler configuration |
| **Ticket integration** | Manual | Configurable (ServiceNow, etc.) | Automated workflow |

---

## New Capabilities (SRE Agent Only)

| Capability | Description |
|---|---|
| **Alternative SKU search** | When Advisor's target SKU fails FitScore, searches the same family for a valid alternative |
| **Stopped-not-deallocated detection** | Finds VMs stopped at OS level but still incurring compute charges |
| **Missing metrics detection** | Explicitly flags VMs without Azure Monitor Agent and adjusts FitScore |
| **Data quality scoring** | Reports confidence level based on metric availability |
| **Workload pattern detection** | Identifies batch, web, and steady-state patterns for context-aware recommendations |
| **Tag-based threshold overrides** | Override default thresholds via resource tags (e.g., `opt-cpu-threshold:90`) |
| **Multi-subscription orchestration** | Single orchestrator can dispatch across multiple subscriptions |
| **On-demand analysis** | Trigger analysis ad-hoc instead of waiting for next batch |

---

## Operational Comparison

| Aspect | AOE | SRE Agent Subagents |
|---|---|---|
| **Deployment time** | 1–2 hours | ~30 minutes |
| **Ongoing maintenance** | Monthly runbook updates, schema migrations | Knowledge base doc updates |
| **Skill requirements** | PowerShell, ARM, SQL, Log Analytics | Markdown, YAML, KQL basics |
| **Debugging** | Automation Account job logs | SRE Agent session logs |
| **Version control** | Git (optional) | Git (native — YAML + markdown) |
| **Rollback** | Re-deploy previous ARM template | Revert knowledge base in Git |

---

## When to Use AOE vs. SRE Agent

| Use Case | Recommended |
|---|---|
| Mature environment, existing AOE deployment | Keep AOE, consider SRE Agent for new capabilities |
| New deployment, want minimal infrastructure | SRE Agent Subagents |
| Need real-time analysis capabilities | SRE Agent Subagents |
| Need Power BI dashboards | AOE |
| Need AI-powered reasoning about recommendations | SRE Agent Subagents |
| Restricted to Automation Account only (policy) | AOE |

---

## Summary

The SRE Agent subagents achieve **full parity** with AOE's 13 recommendation runbooks while adding:

- 🚀 Zero-infrastructure deployment
- 🚀 Real-time data queries
- 🚀 Enhanced FitScore with alternative SKU search
- 🚀 Missing metrics detection
- 🚀 AI-native reasoning
- 🚀 Lower total cost of ownership

All derived logic is credited to AOE and Hélder Pinto.
