# Architecture Decisions

This document captures the key architectural decisions, design rationale, and tradeoffs for the SRE Agent Optimization Engine Subagent project.

---

## 1. Why SRE Agent Over AOE

The Azure Optimization Engine (AOE), created by Hélder Pinto, is an excellent open-source tool for Azure cost optimization. We chose to build on the SRE Agent platform rather than extending AOE directly for the following reasons:

| Factor | AOE | SRE Agent Subagents |
|---|---|---|
| **Infrastructure** | Automation Account + Logic Apps + SQL + Storage | Managed by Azure SRE Agent platform (no infra to maintain) |
| **Maintenance** | Must update runbooks, database schemas, dependencies | Knowledge base documents and YAML configs only |
| **Extensibility** | Requires PowerShell/ARM expertise to extend | Add a new markdown doc to the knowledge base |
| **Real-time capability** | Batch only (daily/weekly schedules) | Can query live data via Azure Monitor tools |
| **AI-native** | No AI reasoning | LLM-powered analysis with tool calling |
| **Cost of ownership** | ~$150–300/month infrastructure | Near-zero (SRE Agent platform cost only) |

> **Important:** We give full credit to AOE and Hélder Pinto. The FitScore methodology, recommendation logic, and many runbook concepts are derived from AOE's approach. This project is a re-implementation on a modern AI-native platform, not a replacement of AOE.

---

## 2. Why the Subagent Pattern

### Single Agent vs. Subagent Architecture

We considered two approaches:

**Option A: Single monolithic agent** with all optimization logic in one knowledge base.

**Option B: Orchestrator + specialist subagents** (chosen), where each domain has its own agent.

### Decision: Subagent Pattern (Option B)

Reasons:

1. **Knowledge base size limits** — SRE Agent knowledge bases have practical size limits. Splitting by domain keeps each knowledge base focused and within limits.
2. **Independent scheduling** — Compute optimization may run daily, while governance checks run weekly. Subagents allow independent schedules.
3. **Blast radius** — A bug in one subagent doesn't affect others.
4. **Team ownership** — Different teams can own different subagents.
5. **Testability** — Each subagent can be tested independently against specific resource types.

### Subagent Roster

```
orchestrator/
├── Dispatches work to specialist subagents
├── Aggregates results
└── Generates summary reports

compute-optimization/
├── VM right-sizing (Advisor + FitScore)
├── Deallocated VM detection
├── Stopped-not-deallocated detection
└── Missing metrics detection

storage-optimization/
├── Unattached disk detection
├── Over-provisioned disk analysis
├── Snapshot lifecycle management
└── Storage tier optimization

network-optimization/
├── Orphaned public IP detection
├── Orphaned NSG detection
├── Empty load balancer detection
└── Unused NAT gateway detection

paas-optimization/
├── App Service Plan right-sizing
├── Idle App Services
├── SQL Database DTU/vCore optimization
└── Underutilized managed services

governance-compliance/
├── Tag compliance auditing
├── Naming convention validation
├── Policy compliance reporting
└── Cost allocation validation
```

---

## 3. Tool Selection Rationale

The SRE Agent platform provides built-in tools that the subagents use. Key tools and why they were chosen:

| Tool | Purpose | Why |
|---|---|---|
| **Azure Resource Graph** | Query resource inventory and configuration | Fast, cross-subscription, supports complex KQL queries |
| **Azure Advisor** | Retrieve cost/performance recommendations | Microsoft's own recommendation engine; source of right-sizing suggestions |
| **Azure Monitor** | Query metrics (CPU, memory, IOPS, network) | Real-time and historical metrics; P50/P95/P99 percentile queries |
| **Azure Activity Log** | Check resource lifecycle events | Detect deallocated duration, last start/stop times |
| **Azure Pricing API** | Estimate savings | Retail pricing for SKU cost comparison |

### Tools NOT Used (and Why)

| Tool | Why Not |
|---|---|
| Azure Cost Management API | Too complex for per-resource cost; Pricing API is simpler for SKU comparison |
| Azure Policy | Read-only agent; policy assignment is out of scope |
| ARM Deployment | Agent is read-only; no resource modifications |

---

## 4. Knowledge Base Design Philosophy

### Principles

1. **Declarative over procedural** — Knowledge base documents describe *what* to check and *how* to reason, not step-by-step code.
2. **Composable** — Each document covers one concept (FitScore, thresholds, queries) and can be referenced by multiple subagents.
3. **Overridable** — Default thresholds can be overridden via resource tags or configuration.
4. **Auditable** — Every recommendation traces back to a knowledge base document and methodology.

### Knowledge Base Structure

```
knowledge-base/
├── FitScore-Methodology.md       → How to calculate FitScore (scoring algorithm)
├── Threshold-Defaults.md         → Default thresholds (CPU >80%, memory >80%, etc.)
├── SKU-Constraint-Rules.md       → Hard constraints (disk count, NIC count, etc.)
├── Resource-Graph-Queries.md     → KQL queries for resource discovery
├── Metric-Collection-Guide.md    → How to query Azure Monitor for P99 metrics
├── Savings-Estimation.md         → How to estimate monthly savings
├── Recommendation-Format.md      → Output format for recommendations
├── Severity-Classification.md    → How to classify severity (Critical/High/Medium/Low)
├── Escalation-Criteria.md        → When to escalate vs auto-recommend
├── Workload-Patterns.md          → How to detect workload patterns (batch, web, etc.)
```

---

## 5. Real-Time vs. Batch Tradeoffs

| Aspect | Batch (AOE Model) | Real-Time (SRE Agent) | Our Approach |
|---|---|---|---|
| **Data freshness** | 24–48 hours stale | Live queries | **Hybrid** — scheduled runs + on-demand |
| **Cost** | Fixed infra cost | Per-query cost | Lower overall (no standing infra) |
| **Metric quality** | Aggregated over time | Point-in-time snapshot | **Scheduled**: 7-day P99 windows |
| **Advisor data** | Snapshot at run time | Live Advisor API | Live query during scheduled run |
| **Scalability** | Scales with Automation Account limits | Scales with SRE Agent platform | Platform-managed |

### Decision: Scheduled with On-Demand Capability

- **Primary mode:** Scheduled runs (daily for compute, weekly for governance)
- **Secondary mode:** On-demand triggering for ad-hoc analysis
- **Metric window:** 7-day P99 percentiles to smooth out spikes
- **Advisor data:** Queried live at each run (always current)

---

## 6. Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        SRE Agent Platform                       │
│                                                                 │
│  ┌──────────────┐     ┌──────────────────────────────────────┐  │
│  │ Orchestrator  │────▶│         Specialist Subagents         │  │
│  │   Subagent    │◀────│  ┌────────┐ ┌─────────┐ ┌────────┐ │  │
│  └──────────────┘     │  │Compute │ │ Storage │ │Network │ │  │
│         │             │  └───┬────┘ └────┬────┘ └───┬────┘ │  │
│         │             │      │           │          │       │  │
│         │             │  ┌───┴───┐ ┌─────┴────┐ ┌───┴────┐ │  │
│         │             │  │ PaaS  │ │Governance│ │  ...   │ │  │
│         │             │  └───┬───┘ └────┬─────┘ └───┬────┘ │  │
│         │             └──────┼──────────┼───────────┼──────┘  │
│         │                    │          │           │          │
│         ▼                    ▼          ▼           ▼          │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    Knowledge Base                        │  │
│  │  FitScore │ Thresholds │ SKU Rules │ Queries │ Formats   │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              │                                  │
└──────────────────────────────┼──────────────────────────────────┘
                               │
                    ┌──────────┼──────────┐
                    │          │          │
                    ▼          ▼          ▼
            ┌──────────┐ ┌─────────┐ ┌──────────┐
            │  Azure   │ │  Azure  │ │  Azure   │
            │ Resource │ │ Advisor │ │ Monitor  │
            │  Graph   │ │   API   │ │   API    │
            └──────────┘ └─────────┘ └──────────┘
                    │          │          │
                    ▼          ▼          ▼
            ┌─────────────────────────────────────┐
            │        Azure Subscriptions          │
            │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐  │
            │  │ VMs │ │Disks│ │ NICs│ │ ASPs│  │
            │  └─────┘ └─────┘ └─────┘ └─────┘  │
            └─────────────────────────────────────┘
```

### Data Flow Steps

1. **Orchestrator** triggers specialist subagents on schedule
2. **Specialist subagent** reads its knowledge base for queries and rules
3. **Subagent** queries Azure Resource Graph for resource inventory
4. **Subagent** queries Azure Advisor for recommendations
5. **Subagent** queries Azure Monitor for performance metrics (P99)
6. **Subagent** calculates FitScore using knowledge base methodology
7. **Subagent** generates recommendations in standardized format
8. **Orchestrator** aggregates results from all subagents
9. **Orchestrator** produces summary report with total savings estimate

---

## 7. Security Model

### Managed Identity

All subagents run under a single **system-assigned Managed Identity** on the SRE Agent. This identity is granted read-only access to target subscriptions.

### Least Privilege RBAC

| Role | Scope | Purpose |
|---|---|---|
| **Reader** | Subscription(s) | Read resource configuration, properties, and tags |
| **Monitoring Reader** | Subscription(s) | Read Azure Monitor metrics and logs |
| **Advisor Reader** | Subscription(s) | Read Azure Advisor recommendations |
| **Log Analytics Reader** | Log Analytics workspace(s) | Read VM Insights data |

### What the Agent CANNOT Do

- ❌ Create, modify, or delete any Azure resources
- ❌ Modify RBAC assignments
- ❌ Access key vaults or secrets
- ❌ Modify Azure Policy
- ❌ Execute any write operations

### RBAC Assignment Script

See [scripts/setup-rbac.sh](../scripts/setup-rbac.sh) for the RBAC setup script.

```bash
# Example: Assign Reader role to Managed Identity
IDENTITY_ID=$(az resource show --ids <sre-agent-resource-id> --query identity.principalId -o tsv)

az role assignment create \
  --assignee $IDENTITY_ID \
  --role "Reader" \
  --scope "/subscriptions/<subscription-id>"
```

### Network Security

- No inbound connectivity required
- Outbound: Azure Resource Manager, Azure Monitor, Azure Advisor (all Azure management plane)
- No access to data plane (no VM SSH, no storage blob access, no database connections)

---

## Appendix: Decision Log

| # | Decision | Date | Rationale |
|---|---|---|---|
| 1 | Use SRE Agent over extending AOE | 2025-01 | Zero-infra, AI-native, real-time capable |
| 2 | Subagent pattern over monolithic | 2025-01 | Scalability, independent scheduling, blast radius |
| 3 | Knowledge base in markdown | 2025-01 | Human-readable, version-controlled, LLM-friendly |
| 4 | Read-only RBAC only | 2025-01 | Safety first; recommendations only, no auto-remediation |
| 5 | 7-day P99 metric window | 2025-01 | Balances freshness with spike smoothing |
| 6 | FitScore 1–5 scale | 2025-01 | Derived from AOE; intuitive, actionable |
