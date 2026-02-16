# Azure Optimization Subagents for SRE Agent

> **Project Type:** Azure SRE Agent Subagent Collection
> **Goal:** Port Azure Optimization Engine (AOE) capabilities into Azure SRE Agent subagents
> **Status:** Planning / Pre-PoC
> **Collaborators:** @zaolinsk · @helderpinto (AOE creator, advisor)
> **Date Started:** February 13, 2026

---

## Table of Contents

1. [Vision](#1-vision)
2. [Background](#2-background)
3. [Architecture](#3-architecture)
4. [Subagent Inventory](#4-subagent-inventory)
5. [Detailed Subagent Designs](#5-detailed-subagent-designs)
6. [Knowledge Base Documents](#6-knowledge-base-documents)
7. [FitScore Methodology](#7-fitscore-methodology)
8. [SRE Agent Tools & Capabilities](#8-sre-agent-tools--capabilities)
9. [Data Sources & API Access](#9-data-sources--api-access)
10. [Output & Reporting](#10-output--reporting)
11. [Testing Strategy](#11-testing-strategy)
12. [Open Questions & Research](#12-open-questions--research)
13. [Upstream AOE Reference](#13-upstream-aoe-reference)
14. [Phased Delivery Plan](#14-phased-delivery-plan)
15. [Repository Structure](#15-repository-structure)
16. [Prerequisites](#16-prerequisites)
17. [Contributing](#17-contributing)
18. [References](#18-references)

---

## 1. Vision

Replace AOE's ~16,000 lines of PowerShell runbooks and ~50 Azure resources with a set of **Azure SRE Agent subagents** defined in ~200 lines of YAML + knowledge base documents.

### What changes

| Dimension | AOE (Current) | SRE Agent Subagents (Target) |
|---|---|---|
| Data collection | 22 PowerShell runbooks exporting to blob/LA | Agent queries APIs directly in real-time |
| Recommendation logic | 13 PowerShell runbooks with hardcoded rules | Subagent instructions + knowledge base docs |
| Infrastructure | ~50 resources (Automation, SQL, Storage, LA) | 3 resources (App Insights, LA, Managed Identity) |
| Scheduling | Azure Automation job schedules | SRE Agent scheduled tasks (cron/natural language) |
| Output | SQL DB rows + Power BI workbook | Email reports, Teams messages, ticket creation |
| Maintenance | Manual PowerShell updates | Update YAML + knowledge base docs |
| Intelligence | Static arithmetic (P99, thresholds) | AI-powered pattern analysis + static rules |

### What stays the same

- FitScore methodology (the most valuable piece)
- Optimization categories (Compute, Storage, Network, PaaS, Governance)
- Threshold defaults (CPU 30%, memory 50%, network 750 Mbps)
- Savings estimation approach
- Recommendation taxonomy

### What gets better

- Real-time API access instead of 7-day stale batch data
- AI understands workload patterns (burst vs steady-state vs batch)
- Can propose alternative SKUs when fit check fails (AOE cannot)
- Automatic ticket creation (PagerDuty, ServiceNow)
- Natural language interaction in Azure portal
- No infrastructure to manage or patch

---

## 2. Background

### Why this project exists

The FinOps Hub AVM team was asked to evaluate bringing AOE into Azure Verified Modules. After deep analysis, we concluded:

1. **AOE is not feasible for AVM** — subscription-scoped deployment, 50+ external script URIs, 50+ `newGuid()` parameters, outdated API versions
2. **AOE is SRE, not FinOps** — 14 of 14 data dimensions are infrastructure/SRE concerns; cost savings is a byproduct
3. **Azure SRE Agent is the right platform** — first-party managed service with subagent extensibility designed exactly for this use case
4. **AOE's creator (Hélder Pinto) supports this direction** — he's interested in a PoC and open to co-authoring

### Key conversation outcomes

- Hélder confirmed AOE has significant tech debt he can't address (team layoffs, 100% customer-facing work)
- AOE's backlog is growing with no capacity to address it
- He explicitly asked to see a PoC
- He's open to co-authoring if the PoC proves viable
- No community poll needed — direct maintainer alignment achieved

---

## 3. Architecture

### SRE Agent deployment model

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure SRE Agent                           │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              Orchestrator Agent                       │   │
│  │  Routes requests to specialist subagents              │   │
│  │  Manages scheduled task execution                     │   │
│  │  Aggregates reports across domains                    │   │
│  └──────────┬───────────────────────────────┬───────────┘   │
│             │                               │               │
│  ┌──────────▼──────────┐   ┌───────────────▼───────────┐   │
│  │ Compute Optimization│   │ Storage Optimization      │   │
│  │ Subagent            │   │ Subagent                  │   │
│  │                     │   │                           │   │
│  │ • VM rightsizing     │   │ • Unattached disks       │   │
│  │ • FitScore validation│   │ • Disk tier optimization │   │
│  │ • Deallocated VMs   │   │ • Storage account config  │   │
│  │ • VMSS analysis     │   │                           │   │
│  │ • HA validation     │   │                           │   │
│  └─────────────────────┘   └───────────────────────────┘   │
│                                                              │
│  ┌─────────────────────┐   ┌───────────────────────────┐   │
│  │ Network Optimization│   │ PaaS Optimization         │   │
│  │ Subagent            │   │ Subagent                  │   │
│  │                     │   │                           │   │
│  │ • Unused LBs        │   │ • App Service Plan sizing │   │
│  │ • Unused App GWs    │   │ • SQL DB DTU/vCore tiers  │   │
│  │ • VNet optimization │   │                           │   │
│  └─────────────────────┘   └───────────────────────────┘   │
│                                                              │
│  ┌─────────────────────┐                                    │
│  │ Governance &         │                                    │
│  │ Compliance Subagent  │                                    │
│  │                     │                                    │
│  │ • Expiring creds    │                                    │
│  │ • Outdated APIs     │                                    │
│  │ • Advisor (non-cost)│                                    │
│  └─────────────────────┘                                    │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              Knowledge Base                           │   │
│  │  • FitScore methodology & thresholds                  │   │
│  │  • SKU constraint validation rules                    │   │
│  │  • Recommendation output format                       │   │
│  │  • Savings estimation formulas                        │   │
│  │  • Escalation & severity criteria                     │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
        │              │               │
        ▼              ▼               ▼
  ┌──────────┐  ┌──────────┐  ┌──────────────┐
  │ Azure    │  │ Azure    │  │ Azure        │
  │ Resource │  │ Monitor  │  │ Advisor      │
  │ Graph    │  │ Metrics  │  │ API          │
  └──────────┘  └──────────┘  └──────────────┘
        │              │               │
        ▼              ▼               ▼
  ┌──────────┐  ┌──────────┐  ┌──────────────┐
  │ Compute  │  │ Billing  │  │ Microsoft    │
  │ SKU API  │  │ API      │  │ Graph        │
  └──────────┘  └──────────┘  └──────────────┘
```

### How subagents interact

1. **Scheduled trigger** fires (e.g., "every Monday at 6 AM")
2. Orchestrator activates the appropriate specialist subagent
3. Subagent queries Azure APIs directly (Resource Graph, Monitor, Advisor, etc.)
4. Subagent applies domain rules from its knowledge base (e.g., FitScore)
5. Subagent generates recommendations with severity, savings estimates, and evidence
6. Output is sent via configured channel (email, Teams, ServiceNow, PagerDuty)
7. Orchestrator aggregates cross-domain summary if multiple subagents ran

---

## 4. Subagent Inventory

### PoC scope (Phase 1)

| # | Subagent | Priority | Rationale |
|---|---|---|---|
| 1 | **Compute Optimization Specialist** | 🔴 P0 | FitScore is the hardest piece — proves the concept |

### Full scope (Phase 2+)

| # | Subagent | Priority | AOE Runbooks Replaced |
|---|---|---|---|
| 2 | **Storage Optimization Specialist** | 🟡 P1 | `UnattachedDisks`, `DiskOptimizations`, `StorageAccountOptimizations` |
| 3 | **Network Optimization Specialist** | 🟡 P1 | `UnusedLoadBalancers`, `UnusedAppGWs`, `VNetOptimizations` |
| 4 | **PaaS Optimization Specialist** | 🟢 P2 | `AppServiceOptimizations`, `SqlDbOptimizations` |
| 5 | **Governance & Compliance Specialist** | 🟢 P2 | `AADExpiringCredentials`, `ARMOptimizations`, `AdvisorAsIs` |
| 6 | **Orchestrator / Coordinator** | 🟢 P2 | Aggregates reports, manages cross-domain scheduling |

---

## 5. Detailed Subagent Designs

### 5.1 Compute Optimization Specialist (PoC)

**Purpose:** Identify VM and VMSS rightsizing opportunities, validate with FitScore, detect idle/orphaned compute resources.

**Replaces AOE runbooks:**
- `Recommend-AdvisorCostAugmented` (FitScore + Advisor rightsizing)
- `Recommend-VMOptimizations` (deallocated/stopped VMs)
- `Recommend-VMSSOptimizations` (VMSS utilization)
- `Recommend-VMsHighAvailability` (availability sets/zones)

**YAML definition:**

```yaml
agent:
  name: "Compute-Optimization-Specialist"
  description: "Analyzes Azure VMs and VMSS for rightsizing opportunities, validates recommendations with FitScore methodology, and detects idle or orphaned compute resources."
  instructions: |
    You are a compute optimization specialist for Azure infrastructure.
    Your expertise covers VM rightsizing, VMSS scaling analysis, and 
    compute resource lifecycle management.

    ## Your workflow

    1. DISCOVER: Query Azure Resource Graph for all VMs and VMSS in the 
       target subscription(s)
    2. ASSESS: For each VM, collect current SKU, disk count, NIC count, 
       and power state
    3. CHECK ADVISOR: Query Azure Advisor for cost recommendations 
       targeting these VMs
    4. VALIDATE: For each Advisor rightsizing recommendation, calculate 
       FitScore using the methodology in your knowledge base
    5. DETECT IDLE: Find VMs deallocated for 30+ days or in 
       "stopped (not deallocated)" state
    6. CHECK HA: Identify VMs not in availability sets or availability zones
    7. REPORT: Generate structured recommendations with severity, 
       savings estimate, FitScore, and evidence

    ## FitScore validation

    Refer to your knowledge base document "FitScore-Methodology.md" for 
    the complete validation procedure. Key points:
    - Query Get-AzComputeResourceSku for target SKU capabilities
    - Validate: MaxDataDiskCount, MaxNetworkInterfaces, UncachedDiskIOPS, 
      UncachedDiskBytesPerSecond
    - Check P99 metrics: CPU (threshold 30%), Memory (threshold 50%), 
      Network (threshold 750 Mbps)
    - FitScore 5 = safe, FitScore 1 = hard constraint violation
    - NEVER recommend a resize with FitScore ≤ 2

    ## Output format

    For each recommendation, provide:
    - Resource ID and name
    - Current SKU → Recommended SKU
    - FitScore (0-5) with breakdown
    - Monthly savings estimate (USD)
    - Severity (Critical / High / Medium / Low)
    - Evidence (which metrics/constraints informed the decision)
    - Risk assessment

    ## Important rules

    - Always use P99 percentiles, never averages
    - Use 7-day lookback minimum for metrics
    - If memory metrics are unavailable (no VM Insights/AMA), note this 
      as a gap and reduce FitScore by 0.5
    - When FitScore fails due to hard constraints, attempt to find 
      alternative SKUs that DO fit (AOE cannot do this — we can)
    - Group recommendations by resource group for actionability

  tools:
    - "RunAzCliReadCommands"
    - "RunAzCliWriteCommands"
    - "ExecutePythonCode"
    - "UploadKnowledgeDocument"
  handoff_description: "Delegate to this agent when the task involves VM or VMSS optimization, rightsizing, compute utilization analysis, or FitScore validation."
  agent_type: Autonomous
```

**Scheduled task:**

```yaml
schedule:
  name: "Weekly Compute Optimization Scan"
  trigger: "0 6 * * 1"  # Every Monday at 6:00 AM UTC
  description: "Run weekly compute optimization analysis across all subscriptions"
  subagent: "Compute-Optimization-Specialist"
  prompt: |
    Perform a complete compute optimization scan:
    1. List all VMs and VMSS across accessible subscriptions
    2. Check Azure Advisor for rightsizing recommendations
    3. Validate each recommendation with FitScore
    4. Detect deallocated VMs (30+ days) and stopped-not-deallocated VMs
    5. Check high availability configuration
    6. Send the report via email to the platform engineering team
```

### 5.2 Storage Optimization Specialist

**Purpose:** Identify unattached disks, over-provisioned storage tiers, and misconfigured storage accounts.

**Replaces AOE runbooks:**
- `Recommend-UnattachedDisks`
- `Recommend-DiskOptimizations`
- `Recommend-StorageAccountOptimizations`

**Key detection logic:**

| Detection | How | Data Source |
|---|---|---|
| Unattached managed disks | `managedBy` property is null/empty | Resource Graph |
| Over-provisioned Premium disks | Actual IOPS < 20% of provisioned IOPS (P99, 7 days) | Azure Monitor |
| Over-provisioned Ultra disks | Actual throughput < 20% of provisioned throughput | Azure Monitor |
| Wrong storage account tier | Hot tier but last access > 30 days | Storage Analytics / Resource Graph |
| Missing lifecycle policies | No lifecycle management rules configured | Resource Graph |
| Snapshot age | Snapshots older than 90 days | Resource Graph |

**YAML definition:** *To be designed in Phase 2*

### 5.3 Network Optimization Specialist

**Purpose:** Identify unused network resources and optimization opportunities.

**Replaces AOE runbooks:**
- `Recommend-UnusedLoadBalancers`
- `Recommend-UnusedAppGWs`
- `Recommend-VNetOptimizations`

**Key detection logic:**

| Detection | How | Data Source |
|---|---|---|
| Empty load balancers | Backend pool count = 0 | Resource Graph |
| Empty App Gateways | Backend pool with 0 targets | Resource Graph |
| Orphaned NSGs | Not associated with any subnet or NIC | Resource Graph |
| Empty subnets | Subnet with 0 connected devices | Resource Graph |
| Unpeered VNets | VNet with no peering connections | Resource Graph |
| Orphaned public IPs | Not associated with any resource | Resource Graph |
| Unused NAT Gateways | Associated subnet has no VMs | Resource Graph + Monitor |

**YAML definition:** *To be designed in Phase 2*

### 5.4 PaaS Optimization Specialist

**Purpose:** Identify over-provisioned App Service Plans and SQL Database tiers.

**Replaces AOE runbooks:**
- `Recommend-AppServiceOptimizations`
- `Recommend-SqlDbOptimizations`

**Key detection logic:**

| Detection | How | Data Source |
|---|---|---|
| Over-provisioned ASP | CPU P99 < 30%, Memory P99 < 50% for 7 days | Azure Monitor |
| Empty App Service Plans | 0 apps hosted on plan | Resource Graph |
| SQL DB DTU waste | DTU utilization P99 < 20% for 7 days | Azure Monitor |
| SQL DB vCore waste | CPU P99 < 20% for 7 days | Azure Monitor |
| Elastic pool candidates | Multiple single DBs with complementary usage patterns | Azure Monitor |

**YAML definition:** *To be designed in Phase 2*

### 5.5 Governance & Compliance Specialist

**Purpose:** Identity hygiene, API version compliance, and non-cost Advisor recommendations.

**Replaces AOE runbooks:**
- `Recommend-AADExpiringCredentials`
- `Recommend-ARMOptimizations`
- `Recommend-AdvisorAsIs`

**Key detection logic:**

| Detection | How | Data Source |
|---|---|---|
| Expiring app credentials | Secrets/certificates expiring within 30 days | Microsoft Graph |
| Expired app credentials | Already expired secrets/certificates | Microsoft Graph |
| Outdated ARM API versions | Resources using API versions > 2 years old | Resource Graph |
| Missing required tags | Resources without mandatory tags | Resource Graph + Azure Policy |
| Non-cost Advisor recommendations | Security, reliability, performance categories | Advisor API |
| Unused role assignments | RBAC assignments for deleted users/groups | Microsoft Graph + RBAC API |

**YAML definition:** *To be designed in Phase 2*

---

## 6. Knowledge Base Documents

The knowledge base is the critical differentiator — it encodes AOE's domain expertise into documents the AI agent can reference. Each document should be markdown format, max file size per SRE Agent limits.

### Required documents

| Document | Purpose | Source | Priority |
|---|---|---|---|
| `FitScore-Methodology.md` | Complete FitScore calculation procedure | AOE's `Recommend-AdvisorCostAugmentedToBlobStorage.ps1` | 🔴 P0 |
| `SKU-Constraint-Rules.md` | Which SKU capabilities to check, hard vs soft constraints | AOE's FitScore logic + `Get-AzComputeResourceSku` docs | 🔴 P0 |
| `Threshold-Defaults.md` | Default thresholds for all metrics with rationale | AOE's variable declarations | 🟡 P1 |
| `Recommendation-Format.md` | Standard output schema for all recommendations | New — based on AOE's SQL schema | 🟡 P1 |
| `Savings-Estimation.md` | How to calculate monthly savings per recommendation type | AOE's pricing logic + Azure Retail Prices API | 🟡 P1 |
| `Severity-Classification.md` | When to classify as Critical/High/Medium/Low | New — based on AOE's implicit logic | 🟡 P1 |
| `Resource-Graph-Queries.md` | Pre-built ARG queries for each resource type | AOE's `Export-ARG*` runbooks | 🟢 P2 |
| `Metric-Collection-Guide.md` | Which Azure Monitor metrics to query, time grains, aggregations | AOE's `Export-AzMonitorMetrics` | 🟢 P2 |
| `Escalation-Criteria.md` | When to create tickets vs email vs just log | New | 🟢 P2 |
| `Workload-Patterns.md` | How to identify burst/steady-state/batch (new capability beyond AOE) | New — AI-native | 🟢 P2 |

### FitScore-Methodology.md outline

This is the single most important document. It must contain:

```markdown
# FitScore Methodology

## Overview
FitScore is a 0-5 validation score for VM rightsizing recommendations.
It ensures that Advisor's suggestions won't break workloads.

## Input
- Advisor recommendation (current SKU → target SKU)
- VM's current configuration (disk count, NIC count)
- VM's observed metrics (P99 over 7 days)
- Target SKU capabilities (from Compute Resource SKU API)

## Calculation procedure

### Step 1: Initialize score = 5

### Step 2: Hard constraint checks (any failure → FitScore = 1)
- IF current attached data disks > target MaxDataDiskCount → SCORE = 1, STOP
- IF current attached NICs > target MaxNetworkInterfaces → SCORE = 1, STOP

### Step 3: Soft constraint checks (deductions)
- IF observed P99 Uncached Disk IOPS ≥ target UncachedDiskIOPS → SCORE -= 1
- IF observed P99 Uncached Disk MiBps ≥ target UncachedDiskBytesPerSecond → SCORE -= 1
- IF observed P99 CPU% ≥ 30% (configurable) → SCORE -= 0.5
- IF observed P99 Memory% ≥ 50% (configurable) → SCORE -= 0.5
- IF observed P99 Network Mbps ≥ 750 (configurable) → SCORE -= 0.1

### Step 4: Missing data adjustments
- IF memory metrics unavailable → SCORE -= 0.5, note "No VM Insights/AMA"
- IF disk IOPS metrics unavailable → note gap but don't adjust

### Step 5: Interpret
- 5.0: Safe to resize, all constraints clear
- 4.0-4.9: Likely safe, minor soft constraint proximity
- 3.0-3.9: Caution, review metrics before proceeding
- 2.0-2.9: Risky, significant constraint pressure
- 1.0-1.9: Do NOT resize, hard constraint violation
- 0.0-0.9: Do NOT resize, multiple hard violations

### Step 6 (NEW — beyond AOE): Alternative SKU search
- IF FitScore ≤ 2 for the Advisor-suggested SKU:
  - Query all available SKUs in the same region
  - Filter to SKUs with lower cost than current
  - Run FitScore against each candidate
  - Return the best-fit alternative (highest FitScore with savings)
```

---

## 7. FitScore Methodology

### Deep dive: What AOE does today

Source: `Recommend-AdvisorCostAugmentedToBlobStorage.ps1` from `microsoft/finops-toolkit`

#### P99 metric queries (Azure Monitor)

```
Perf
| where TimeGenerated > ago(7d)
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| summarize P99_CPU = percentile(CounterValue, 99) by Computer
```

```
Perf
| where TimeGenerated > ago(7d)
| where ObjectName == "Memory" and CounterName == "% Used Memory"
| summarize P99_Memory = percentile(CounterValue, 99) by Computer
```

```
Perf
| where TimeGenerated > ago(7d)
| where ObjectName == "Network" and CounterName == "Total Bytes Transmitted"
| summarize P99_Network = percentile(CounterValue, 99) by Computer
```

**Time grain:** 1 hour
**Lookback:** 7 days
**Aggregation:** P99 (99th percentile)

#### SKU capability lookup

AOE uses `Get-AzComputeResourceSku` which returns:

```json
{
  "name": "Standard_D4s_v5",
  "capabilities": [
    { "name": "MaxDataDiskCount", "value": "8" },
    { "name": "MaxNetworkInterfaces", "value": "2" },
    { "name": "UncachedDiskIOPS", "value": "6400" },
    { "name": "UncachedDiskBytesPerSecond", "value": "100663296" },
    { "name": "vCPUs", "value": "4" },
    { "name": "MemoryGB", "value": "16" }
  ]
}
```

**SRE Agent equivalent:** `az vm list-skus --location <location> --size <sku> --output json`

#### What AOE CANNOT do (our improvements)

| Limitation | Our Approach |
|---|---|
| Can't propose alternatives when fit fails | Iterate SKU catalog, run FitScore on each candidate |
| Uses only P99 — no pattern awareness | AI can analyze time series shape (burst vs flat vs cyclical) |
| 7-day only lookback | Query 30-day or 90-day metrics for seasonal workloads |
| No workload type awareness | Cross-reference with resource tags, app type, service classification |
| Static thresholds | Allow per-subscription or per-resource-group threshold overrides |
| No confidence intervals | AI can express "80% confident this resize is safe" vs binary yes/no |

---

## 8. SRE Agent Tools & Capabilities

### Available built-in tools

These are the tools SRE Agent provides to subagents. We need to understand exactly what's available to design effective instructions.

| Tool | What It Does | Needed For |
|---|---|---|
| `RunAzCliReadCommands` | Execute read-only Azure CLI commands | `az vm list-skus`, `az advisor recommendation list`, Resource Graph queries, `az monitor log-analytics query` for KQL/P99 metrics, `az monitor metrics list` for platform metrics |
| `RunAzCliWriteCommands` | Execute write Azure CLI commands | Future: auto-remediation (Phase 3+) |
| `GetAzCliHelp` | Get help for Azure CLI commands | Command syntax reference |
| `ExecutePythonCode` | Execute Python snippets | Complex FitScore calculations, data processing |
| `UploadKnowledgeDocument` | Save documents to agent KB | Report persistence, trend analysis |
| `GetActivityLogsSummary` | Query Activity Log | Deallocated VM detection, change history |
| `GetArmResourceAsJson` | Get raw ARM resource JSON | VM properties, disk details |
| `CheckIfResourceExists` | Check resource existence | Pre-query validation |
| `GetDimensionNames` | Get metric dimension names | Metric metadata discovery |
| `GetCurrentUtcTime` | Get current UTC time | Report timestamps |
| `SearchMemory` | Search agent memory | Cross-session context |

### Confirmed tool mappings

- [x] **`RunAzCliReadCommands` supports Resource Graph queries** — `az graph query -q "..."`
- [x] **`RunAzCliReadCommands` supports Log Analytics KQL** — `az monitor log-analytics query --workspace <id> --analytics-query "..."`
- [x] **`RunAzCliReadCommands` supports REST API calls** — `az rest --url "https://prices.azure.com/..."`
- [x] **`ExecutePythonCode` is the correct name** (not `RunPythonCode`)
- [x] **No `AzureMonitorQuery` tool exists** — use `RunAzCliReadCommands` with `az monitor log-analytics query`
- [x] **No `SendOutlookEmail` tool exists** — use `UploadKnowledgeDocument` + conversation output
- [x] **No `PlotTimeSeriesData` tool exists** — use `ExecutePythonCode` if visualization needed
- [x] **No `SearchWeb` tool exists** — use `RunAzCliReadCommands` with `az rest` for pricing API

## 9. Data Sources & API Access

### APIs the subagents need to call

| API | Purpose | Azure CLI Command | Auth Required |
|---|---|---|---|
| **Azure Resource Graph** | List all resources by type | `az graph query -q "Resources \| where type =~ 'microsoft.compute/virtualMachines'"` | Reader role |
| **Azure Monitor Metrics** | P99 CPU, memory, disk, network | `az monitor metrics list --resource <id> --metric "Percentage CPU"` | Monitoring Reader |
| **Azure Advisor** | Rightsizing recommendations | `az advisor recommendation list --category Cost` | Reader role |
| **Compute Resource SKUs** | SKU capabilities (disk count, IOPS, etc.) | `az vm list-skus --location <loc> --size <sku>` | Reader role |
| **Azure Retail Prices** | Current VM pricing for savings calc | REST: `https://prices.azure.com/api/retail/prices` | None (public API) |
| **Microsoft Graph** | App registration credentials | `az ad app list --query "[].{id:id, creds:passwordCredentials}"` | Directory Reader |
| **Azure Policy** | Compliance state | `az policy state list` | Reader role |
| **RBAC** | Role assignments | `az role assignment list` | Reader role |

### Managed Identity permissions

The SRE Agent's Managed Identity needs these RBAC roles:

| Role | Scope | Purpose |
|---|---|---|
| **Reader** | Subscription(s) | Resource Graph queries, resource enumeration |
| **Monitoring Reader** | Subscription(s) | Azure Monitor metrics access |
| **Advisor Reader** | Subscription(s) | Advisor recommendation access |
| **Directory Reader** | Microsoft Entra ID tenant | App registration credential checks (Governance subagent) |

### Multi-subscription support

- [ ] **Research:** Can SRE Agent's Managed Identity be granted access across subscriptions?
- [ ] **Research:** Can Management Group-scoped RBAC work with SRE Agent?
- [ ] **Research:** How does Resource Graph handle cross-subscription queries in SRE Agent context?

---

## 10. Output & Reporting

### Recommendation output schema

Every recommendation should follow a consistent structure:

```json
{
  "id": "rec-<uuid>",
  "timestamp": "2026-02-13T06:00:00Z",
  "category": "Compute",
  "subcategory": "VM Rightsizing",
  "severity": "High",
  "resourceId": "/subscriptions/.../Microsoft.Compute/virtualMachines/web-prod-01",
  "resourceName": "web-prod-01",
  "resourceGroup": "rg-production",
  "subscription": "Production",
  "currentState": {
    "sku": "Standard_D8s_v5",
    "monthlyCost": 280.32
  },
  "recommendation": {
    "action": "Resize",
    "targetSku": "Standard_D4s_v5",
    "monthlyCost": 140.16,
    "monthlySavings": 140.16,
    "annualSavings": 1681.92
  },
  "fitScore": {
    "score": 4.5,
    "breakdown": {
      "diskCount": "PASS (2 attached, target max 8)",
      "nicCount": "PASS (1 attached, target max 2)",
      "diskIOPS": "PASS (P99: 3200, target cap: 6400)",
      "diskThroughput": "PASS (P99: 45 MiBps, target cap: 96 MiBps)",
      "cpu": "WARN -0.5 (P99: 35%, threshold: 30%)",
      "memory": "PASS (P99: 42%, threshold: 50%)",
      "network": "PASS (P99: 120 Mbps, threshold: 750 Mbps)"
    }
  },
  "evidence": {
    "metricsLookback": "7 days",
    "metricsTimeGrain": "1 hour",
    "advisorRecommendationId": "<guid>",
    "dataQuality": "Full (all metrics available)"
  },
  "riskAssessment": "Low — all hard constraints pass, single soft constraint (CPU at P99 35%) is close to threshold but within safe range"
}
```

### Delivery channels

| Channel | Use Case | Configuration |
|---|---|---|
| **Knowledge Base** | Primary report persistence | `UploadKnowledgeDocument` tool |
| **Conversation output** | Immediate review in chat/playground | Always output alongside KB save |
| **Teams channel** | High-severity alerts (FitScore ≤ 2 on existing resources) | Teams webhook (if supported) |
| **ServiceNow** | Create change requests for approved rightsizing | ServiceNow MCP connector |
| **PagerDuty** | Critical findings (e.g., 100+ deallocated VMs) | PagerDuty MCP connector |
| **Log Analytics** | Audit trail of all recommendations | Custom log via SRE Agent's built-in LA |

### Report structure

Weekly email report should include:

1. **Executive summary** — total findings, total potential savings
2. **By category** — Compute / Storage / Network / PaaS / Governance breakdown
3. **Top 10 by savings** — highest dollar impact recommendations
4. **Critical findings** — anything requiring immediate attention
5. **Trend** — comparison to previous week (new findings, resolved findings)

---

## 11. Testing Strategy

### Unit testing subagent logic

| Test | Method | What It Validates |
|---|---|---|
| FitScore calculation | Mock SKU capabilities + mock metrics → expected score | Core algorithm correctness |
| Hard constraint detection | Disk count > max, NIC count > max | FitScore = 1 on violations |
| Missing metrics handling | No memory data → score adjustment | Graceful degradation |
| Alternative SKU search | FitScore fails → find next best SKU | New capability works |
| Savings calculation | Current price - target price = expected savings | Financial accuracy |

### Integration testing

| Test | Method | What It Validates |
|---|---|---|
| Real VM scan | Run against a test subscription with known VMs | End-to-end data flow |
| Advisor integration | Subscription with active Advisor recommendations | Recommendation ingestion |
| Multi-subscription | Agent with access to 2+ subscriptions | Cross-subscription queries |
| Large scale | Subscription with 100+ VMs | Performance, pagination, output size |

### Test infrastructure needed

- [ ] Azure subscription with test VMs (various sizes, some intentionally oversized)
- [ ] VMs with and without VM Insights/AMA (to test memory metric gaps)
- [ ] VMs in deallocated state (30+ days)
- [ ] VMs with attached disks near SKU limits
- [ ] Advisor recommendations active on at least some VMs
- [ ] SRE Agent resource (requires Preview access)

### Comparison testing (AOE parity)

- [ ] Run AOE against the test subscription
- [ ] Run our Compute Optimization subagent against the same subscription
- [ ] Compare: same resources identified? Same FitScores? Same savings estimates?
- [ ] Document any intentional differences (improvements over AOE)

---

## 12. Open Questions & Research

### SRE Agent platform questions

| # | Question | Status | Impact |
|---|---|---|---|
| 1 | **What SRE Agent tools are actually available?** Docs mention several but exact names and capabilities may differ | ❓ Unresolved | Determines what subagent instructions can reference |
| 2 | **Can `RunAzCliReadCommands` run `az graph query`?** Resource Graph is the primary data source | ❓ Unresolved | Core functionality — blocks everything |
| 3 | **Can `RunAzCliReadCommands` run `az vm list-skus`?** Needed for FitScore SKU capability lookup | ❓ Unresolved | Blocks FitScore implementation |
| 4 | **What is the output size limit per tool call?** Large subscriptions may return 1000+ VMs | ❓ Unresolved | Need pagination strategy |
| 5 | **Can subagents call other subagents?** Orchestrator → Specialist handoff pattern | ❓ Unresolved | Affects architecture |
| 6 | **Can scheduled tasks pass parameters?** e.g., target subscription ID | ❓ Unresolved | Affects multi-subscription design |
| 7 | **Is SRE Agent available in all Azure regions?** | ❓ Unresolved | Deployment planning |
| 8 | **What's the SRE Agent SLA / availability?** Preview = no SLA, but what about GA? | ❓ Unresolved | Production readiness |
| 9 | **Can knowledge base docs reference each other?** e.g., instructions say "see FitScore-Methodology.md" | ❓ Unresolved | Knowledge base design |
| 10 | **Max knowledge base size?** Docs say 1,000 files — but max per-file size? Total size? | ❓ Unresolved | Knowledge base scope |

### Technical design questions

| # | Question | Status | Impact |
|---|---|---|---|
| 11 | **How to handle Azure Retail Prices API?** It's a public REST API, not Azure CLI | ❓ Unresolved | Savings calculation accuracy |
| 12 | **How to persist recommendation history?** AOE uses SQL DB. What do we use? | ❓ Unresolved | Trend comparison (week-over-week) |
| 13 | **How to handle metric time series analysis?** Can the AI actually identify burst patterns? | ❓ Unresolved | Key improvement over AOE |
| 14 | **How to handle per-subscription or per-RG threshold overrides?** Where to store configuration? | ❓ Unresolved | Flexibility for different workload tiers |
| 15 | **How to handle rate limiting?** Advisor, Resource Graph, and Monitor all have API limits | ❓ Unresolved | Large-scale reliability |

### Stakeholder questions

| # | Question | Status | Impact |
|---|---|---|---|
| 16 | **Does the SRE Agent team welcome community subagent contributions?** | ❓ Unresolved | Contribution path |
| 17 | **Is there a subagent marketplace or gallery planned?** | ❓ Unresolved | Distribution strategy |
| 18 | **Can we contribute to `microsoft/sre-agent/samples/`?** | ❓ Unresolved | Upstream contribution |
| 19 | **Does Hélder want co-author credit on specific subagents?** | ❓ Ask when sharing PoC | Attribution |
| 20 | **Should this live in `microsoft/finops-toolkit` or `microsoft/sre-agent` or standalone?** | ❓ Unresolved | Repo ownership |

---

## 13. Upstream AOE Reference

### Source code to study

All files are in `microsoft/finops-toolkit` repo under `dev/src/optimization-engine/`:

#### Critical for PoC (read these first)

| File | Why |
|---|---|
| `runbooks/recommendations/Recommend-AdvisorCostAugmentedToBlobStorage.ps1` | **FitScore implementation** — the most important file. Contains SKU capability lookup, constraint validation, P99 metric queries |
| `runbooks/recommendations/Recommend-VMOptimizationsToBlobStorage.ps1` | Deallocated/stopped VM detection logic |
| `runbooks/data-collection/Export-ARGVirtualMachinesPropertiesToBlobStorage.ps1` | Resource Graph query for VMs — reference for our ARG queries |
| `runbooks/data-collection/Export-AzMonitorMetricsToBlobStorage.ps1` | Which metrics are collected, time grains, aggregation methods |

#### Useful for Phase 2+

| File | Why |
|---|---|
| `runbooks/recommendations/Recommend-UnattachedDisksToBlobStorage.ps1` | Storage detection logic |
| `runbooks/recommendations/Recommend-DiskOptimizationsToBlobStorage.ps1` | Disk tier analysis |
| `runbooks/recommendations/Recommend-UnusedLoadBalancersToBlobStorage.ps1` | Network detection logic |
| `runbooks/recommendations/Recommend-AppServiceOptimizationsToBlobStorage.ps1` | PaaS analysis |
| `runbooks/recommendations/Recommend-AADExpiringCredentialsToBlobStorage.ps1` | Governance checks |

#### Architecture reference

| File | Why |
|---|---|
| `azuredeploy.bicep` | Understand full AOE deployment topology |
| `azuredeploy-nested.bicep` | Understand resource dependencies |
| `README.md` | AOE's own documentation and configuration options |

---

## 14. Phased Delivery Plan

### Phase 1: Compute PoC (Target: 2-3 weeks)

| Week | Deliverable |
|---|---|
| Week 1 | SRE Agent provisioned. Compute subagent YAML created. FitScore-Methodology.md knowledge base written. Basic scheduled task configured. |
| Week 2 | Test against subscription with known VMs. Validate FitScore output against manual Advisor check. Fix instruction gaps. |
| Week 3 | Run parallel with AOE on same subscription. Compare results. Document differences. Share with Hélder for feedback. |

**PoC success criteria:**
- [ ] Subagent runs on schedule without errors
- [ ] Correctly identifies at least 3 VM optimization opportunities
- [ ] FitScore matches AOE's calculation (within 0.5 tolerance)
- [ ] Correctly detects deallocated VMs
- [ ] Generates readable email report
- [ ] Hélder reviews and agrees it captures the core AOE value

### Phase 2: Remaining subagents (Target: 4-6 weeks)

| Week | Deliverable |
|---|---|
| Week 4-5 | Storage + Network subagents. Test individually. |
| Week 6-7 | PaaS + Governance subagents. Test individually. |
| Week 8-9 | Orchestrator agent. Cross-domain reporting. Integration testing. |

### Phase 3: Production hardening (Target: 4 weeks)

| Week | Deliverable |
|---|---|
| Week 10-11 | Multi-subscription support. Pagination handling. Error recovery. |
| Week 12-13 | Reporting polish (email templates, Teams integration, ticket creation). Week-over-week trend comparison. |

### Phase 4: Community contribution (Timing: After SRE Agent GA)

| Deliverable | Target |
|---|---|
| File feature request on `microsoft/sre-agent` | After PoC validated |
| Submit subagent YAMLs to `microsoft/sre-agent/samples/` | After Phase 2 complete |
| Publish blog post / migration guide | After Phase 3 complete |
| Present at community call (FinOps Toolkit or SRE Agent) | When invited |

---

## 15. Repository Structure

Proposed repo layout:

```
azure-optimization-subagents/
├── README.md                           # This file
├── LICENSE
├── CHANGELOG.md
├── .gitignore
│
├── subagents/
│   ├── compute-optimization/
│   │   ├── agent.yaml                  # Subagent definition
│   │   ├── schedule.yaml               # Scheduled task definition
│   │   └── README.md                   # Subagent-specific docs
│   │
│   ├── storage-optimization/
│   │   ├── agent.yaml
│   │   ├── schedule.yaml
│   │   └── README.md
│   │
│   ├── network-optimization/
│   │   ├── agent.yaml
│   │   ├── schedule.yaml
│   │   └── README.md
│   │
│   ├── paas-optimization/
│   │   ├── agent.yaml
│   │   ├── schedule.yaml
│   │   └── README.md
│   │
│   ├── governance-compliance/
│   │   ├── agent.yaml
│   │   ├── schedule.yaml
│   │   └── README.md
│   │
│   └── orchestrator/
│       ├── agent.yaml
│       ├── schedule.yaml
│       └── README.md
│
├── knowledge-base/
│   ├── FitScore-Methodology.md         # Core FitScore algorithm
│   ├── SKU-Constraint-Rules.md         # SKU capability validation
│   ├── Threshold-Defaults.md           # Default metric thresholds
│   ├── Recommendation-Format.md        # Output schema
│   ├── Savings-Estimation.md           # Pricing calculation methods
│   ├── Severity-Classification.md      # Alert severity rules
│   ├── Resource-Graph-Queries.md       # Pre-built ARG queries
│   ├── Metric-Collection-Guide.md      # Azure Monitor query patterns
│   ├── Escalation-Criteria.md          # When to create tickets
│   └── Workload-Patterns.md            # Burst/steady/batch identification
│
├── tests/
│   ├── test-subscription-setup.md      # How to set up test environment
│   ├── fitscore-test-cases.md          # Expected inputs/outputs for FitScore
│   ├── aoe-comparison/
│   │   ├── run-comparison.md           # How to run AOE + subagent side-by-side
│   │   └── comparison-results.md       # Documented differences
│   └── scenarios/
│       ├── oversized-vm.md             # Test: VM with low utilization
│       ├── hard-constraint.md          # Test: Resize would break disk count
│       ├── deallocated-vm.md           # Test: VM off for 30+ days
│       ├── missing-metrics.md          # Test: VM without VM Insights
│       └── alternative-sku.md          # Test: FitScore fails, find alternative
│
├── docs/
│   ├── architecture.md                 # Detailed architecture decisions
│   ├── aoe-comparison.md               # AOE vs Subagents feature matrix
│   ├── deployment-guide.md             # How to deploy in your environment
│   ├── configuration.md                # Customizing thresholds, subscriptions
│   └── contributing.md                 # How to contribute new subagents
│
└── scripts/
    ├── deploy-sre-agent.sh             # Provision SRE Agent + configure identity
    ├── setup-rbac.sh                   # Grant required roles to Managed Identity
    └── validate-access.sh              # Verify all APIs are accessible
```

---

## 16. Prerequisites

### Azure resources needed

| Resource | Purpose | Cost |
|---|---|---|
| Azure SRE Agent (Preview) | Host the subagents | Preview pricing TBD |
| Test subscription with VMs | Validate against real resources | Existing / lab |

### Access required

| Access | How to Get |
|---|---|
| SRE Agent Preview | [Request access](https://learn.microsoft.com/en-us/azure/sre-agent/overview) or check if already available |
| `microsoft/sre-agent` GitHub repo | Public — already accessible |
| `microsoft/finops-toolkit` GitHub repo | Public — already accessible |

### Skills needed

| Skill | For |
|---|---|
| YAML authoring | Subagent definitions |
| Azure Monitor / KQL | Metric queries, Log Analytics |
| Azure Resource Graph | Resource enumeration queries |
| Azure RBAC | Managed Identity permissions |
| Markdown | Knowledge base documents |
| Azure CLI | Testing, validation, deployment scripts |

### Tools needed

| Tool | Purpose |
|---|---|
| Azure CLI (`az`) | Resource management, testing |
| VS Code | YAML + Markdown editing |
| Azure portal | SRE Agent management, subagent builder UI |
| Git | Version control |

---

## 17. Contributing

### Current contributors

| Person | Role | Availability |
|---|---|---|
| **@zaolinsk** | Project lead, PoC developer | Active |
| **@helderpinto** | AOE creator, domain expert, advisor | Limited — feedback when available |

### How Hélder is involved

- **Not actively building** — his team was reduced in layoffs, he's 100% customer-facing
- **Available for feedback** — review PoC results, validate FitScore accuracy
- **Open to co-authoring** — if the PoC proves viable and he has energy
- **Credit:** All AOE-derived logic should credit Hélder and the FinOps Toolkit team

### Attribution

This project builds on the Azure Optimization Engine created by [@helderpinto](https://github.com/helderpinto) as part of the [FinOps Toolkit](https://github.com/microsoft/finops-toolkit). The FitScore methodology, threshold defaults, and recommendation categories are derived from AOE with the creator's knowledge and support.

---

## 18. References

### SRE Agent documentation

- [Azure SRE Agent Overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview)
- [Subagent Builder Overview](https://learn.microsoft.com/en-us/azure/sre-agent/subagent-builder-overview)
- [Subagent Scenarios](https://learn.microsoft.com/en-us/azure/sre-agent/subagent-builder-scenarios)
- [SRE Agent GitHub](https://github.com/microsoft/sre-agent)

### AOE source code

- [AOE Source](https://github.com/microsoft/finops-toolkit/tree/dev/src/optimization-engine)
- [AOE README](https://github.com/microsoft/finops-toolkit/blob/dev/src/optimization-engine/README.md)
- [FitScore Runbook](https://github.com/microsoft/finops-toolkit/blob/dev/src/optimization-engine/runbooks/recommendations/Recommend-AdvisorCostAugmentedToBlobStorage.ps1)
- [VM Optimization Runbook](https://github.com/microsoft/finops-toolkit/blob/dev/src/optimization-engine/runbooks/recommendations/Recommend-VMOptimizationsToBlobStorage.ps1)

### Azure API references

- [Azure Resource Graph REST API](https://learn.microsoft.com/en-us/rest/api/azureresourcegraph/)
- [Azure Monitor Metrics REST API](https://learn.microsoft.com/en-us/rest/api/monitor/metrics/list)
- [Azure Advisor REST API](https://learn.microsoft.com/en-us/rest/api/advisor/)
- [Compute Resource SKUs REST API](https://learn.microsoft.com/en-us/rest/api/compute/resource-skus/list)
- [Azure Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices)

### Related discussions

- [FinOps Toolkit Discussion #1899 — Future of the FinOps Hub Toolkit](https://github.com/microsoft/finops-toolkit/discussions/1899)
- [FinOps Toolkit Discussion #1825 — AOE Discussion](https://github.com/microsoft/finops-toolkit/discussions/1825)
- [FinOps Foundation Framework](https://www.finops.org/framework/)
