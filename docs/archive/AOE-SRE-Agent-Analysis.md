# Azure Optimization Engine → Azure SRE Agent: Analysis & Recommendation

> **Date:** February 13, 2026
> **Author:** FinOps Hub AVM Team
> **Status:** Community feedback requested
> **Related:** [microsoft/finops-toolkit](https://github.com/microsoft/finops-toolkit) · [microsoft/sre-agent](https://github.com/microsoft/sre-agent)

---

## 1. What is Azure SRE Agent?

[Azure SRE Agent](https://learn.microsoft.com/en-us/azure/sre-agent/overview) (Preview) is a first-party Azure managed service that brings AI-powered automation to Site Reliability Engineering practices. It reduces manual operational effort, improves system uptime, and delivers consistent operational outcomes with minimal human intervention.

### Core capabilities

| Capability | Description |
|---|---|
| **Azure service management** | Manages all Azure services through Azure CLI and REST APIs — compute, storage, networking, databases, monitoring |
| **Incident automation** | Connects to Azure Monitor, PagerDuty, and ServiceNow to automate triage, mitigation, and resolution |
| **Scheduled workflows** | Proactive alerting and actions on defined schedules (cron, presets, or natural language) |
| **Subagent builder** | Create specialized autonomous agents with custom instructions, tools, knowledge bases, and handoff rules |
| **Integrations** | Azure Monitor, App Insights, Log Analytics, Grafana, GitHub, Azure DevOps, MCP servers |

### How it works

SRE Agent operates through multiple automation mechanisms:

- **Built-in Azure knowledge** — preconfigured understanding of Azure services with optimized operational patterns
- **Custom runbooks** — execute Azure CLI commands and REST API calls for any Azure service
- **Subagent extensibility** — build specialized agents for specific services (VMs, databases, networking)
- **External integrations** — connect to monitoring, incident management, and source control systems via MCP
- **Knowledge bases** — upload organizational runbooks, architecture docs, and troubleshooting guides (markdown/text, up to 1,000 files per agent)

### Deployment footprint

When you create an SRE Agent, Azure automatically provisions:

- Azure Application Insights
- Log Analytics workspace
- Managed Identity

That's it. No Automation Accounts, no SQL databases, no storage containers, no custom Log Analytics tables.

### Subagent architecture

Subagents are defined via YAML with:

```yaml
agent:
  name: "Specialist-Name"
  description: "What this agent does"
  instructions: |
    Natural language instructions describing the agent's
    expertise, analytical approach, tools to use, and
    output format.
  tools:
    - "RunAzCliReadCommands"
    - "RunAzCliWriteCommands"
    - "ExecutePythonCode"
    - "UploadKnowledgeDocument"
  handoff_description: "When to delegate to this agent"
  agent_type: Autonomous
```

Subagents can be triggered by:

- **Incidents** — Azure Monitor alerts, PagerDuty, ServiceNow
- **Schedules** — cron expressions, preset intervals, natural language ("every weekday at 9 AM")
- **Manual chat** — interactive conversation in the Azure portal

---

## 2. What is Azure Optimization Engine (AOE)?

The [Azure Optimization Engine](https://github.com/microsoft/finops-toolkit/tree/dev/src/optimization-engine) is a community-maintained solution within the [FinOps Toolkit](https://github.com/microsoft/finops-toolkit) that generates weekly infrastructure optimization recommendations. It was created by [@helderpinto](https://github.com/helderpinto) and is deployed as a self-managed set of Azure resources.

### Architecture

AOE follows a batch collect → store → ingest → query → recommend pipeline:

```
┌──────────────────────────────────────────────────────────────────────┐
│                     Azure Automation Account                         │
│  ┌─────────────────┐    ┌──────────────────┐    ┌────────────────┐  │
│  │ 22 Data          │    │ 13 Recommendation│    │ Maintenance    │  │
│  │ Collection       │    │ Runbooks         │    │ Runbooks       │  │
│  │ Runbooks         │    │                  │    │                │  │
│  └────────┬─────────┘    └────────┬─────────┘    └────────────────┘  │
│           │                       │                                   │
└───────────┼───────────────────────┼───────────────────────────────────┘
            │                       │
            ▼                       ▼
┌──────────────────────┐  ┌──────────────────────┐
│  Azure Blob Storage  │  │  Azure Blob Storage  │
│  (20+ containers)    │  │  (recommendations)   │
│  CSV exports         │  │  JSON exports        │
└──────────┬───────────┘  └──────────┬───────────┘
           │                          │
           ▼                          ▼
┌──────────────────────┐  ┌──────────────────────┐
│  Log Analytics       │  │  Azure SQL Database  │
│  (15+ custom tables) │  │  (recommendations +  │
│  ARGVirtualMachine_CL│  │   filters + control) │
│  AzureAdvisor_CL     │  └──────────┬───────────┘
│  AzureConsumption_CL │             │
│  Pricesheet_CL       │             ▼
│  Perf (built-in)     │  ┌──────────────────────┐
│  etc.                │  │  Power BI Workbook    │
└──────────────────────┘  │  (recommendations     │
                          │   dashboard)           │
                          └──────────────────────┘
```

### Deployment footprint

AOE deploys approximately **50 Azure resources**:

- Azure Automation Account with 35+ runbooks
- Azure SQL Database (recommendations + control tables)
- Log Analytics workspace (15+ custom tables)
- Azure Storage account (20+ blob containers, Cool tier)
- Multiple RBAC role assignments
- Scheduled jobs for each runbook

### Data collection runbooks (22 total)

| Runbook | Data Source | Target LA Table |
|---|---|---|
| `Export-ARGVirtualMachinesProperties` | Resource Graph | `ARGVirtualMachine_CL` |
| `Export-ARGManagedDisksProperties` | Resource Graph | `ARGManagedDisk_CL` |
| `Export-ARGVMSSProperties` | Resource Graph | `ARGVMSS_CL` |
| `Export-ARGSqlDatabaseProperties` | Resource Graph | `ARGSqlDatabase_CL` |
| `Export-ARGAppServicePlanProperties` | Resource Graph | `ARGAppServicePlan_CL` |
| `Export-ARGNICProperties` | Resource Graph | `ARGNIC_CL` |
| `Export-ARGNSGProperties` | Resource Graph | `ARGNSG_CL` |
| `Export-ARGPublicIpProperties` | Resource Graph | `ARGPublicIp_CL` |
| `Export-ARGVNetProperties` | Resource Graph | `ARGVNet_CL` |
| `Export-ARGLoadBalancerProperties` | Resource Graph | `ARGLoadBalancer_CL` |
| `Export-ARGAvailabilitySetProperties` | Resource Graph | `ARGAvailabilitySet_CL` |
| `Export-ARGAppGatewayProperties` | Resource Graph | `ARGAppGateway_CL` |
| `Export-ARGUnmanagedDisksProperties` | Resource Graph | `ARGUnmanagedDisk_CL` |
| `Export-ARGResourceContainersProperties` | Resource Graph | `ARGResourceContainers_CL` |
| `Export-AdvisorRecommendations` | Advisor API | `AzureAdvisor_CL` |
| `Export-Consumption` | Consumption API | `AzureConsumption_CL` |
| `Export-PriceSheet` | Billing API | `Pricesheet_CL` |
| `Export-AzMonitorMetrics` | Azure Monitor | `Perf` (built-in) |
| `Export-PolicyCompliance` | Policy API | `AzurePolicyCompliance_CL` |
| `Export-RBACAssignments` | RBAC API | `AzureRBAC_CL` |
| `Export-AADObjects` | Microsoft Graph | `AADObjects_CL` |
| `Export-ReservationsUsage` | Billing API | `AzureReservations_CL` |

### Recommendation runbooks (13 total)

| Runbook | Domain | What It Detects |
|---|---|---|
| `Recommend-AdvisorCostAugmented` | Compute | Advisor rightsizing + SKU FitScore validation |
| `Recommend-VMOptimizations` | Compute | Deallocated VMs (30+ days), stopped-not-deallocated VMs |
| `Recommend-VMSSOptimizations` | Compute | VMSS utilization analysis |
| `Recommend-VMsHighAvailability` | Compute | VMs not in availability sets or zones |
| `Recommend-UnattachedDisks` | Storage | Managed disks with no `managedBy` reference |
| `Recommend-DiskOptimizations` | Storage | Over-provisioned Premium/Ultra disks |
| `Recommend-StorageAccountOptimizations` | Storage | Wrong access tier, missing lifecycle policies |
| `Recommend-UnusedLoadBalancers` | Network | Load balancers with empty backend pools |
| `Recommend-UnusedAppGWs` | Network | Application gateways with empty backend pools |
| `Recommend-VNetOptimizations` | Network | Empty subnets, orphaned NSGs, unpeered VNets |
| `Recommend-AppServiceOptimizations` | PaaS | Over-provisioned App Service Plans |
| `Recommend-SqlDbOptimizations` | PaaS | SQL DB DTU/vCore tier optimization |
| `Recommend-AADExpiringCredentials` | Governance | App registrations with expiring secrets/certs |
| `Recommend-ARMOptimizations` | Governance | Outdated API versions, missing tags |
| `Recommend-AdvisorAsIs` | Governance | All non-cost Advisor categories (security, reliability, performance) |

### The FitScore system

AOE's most valuable feature is its **FitScore** — a 0-5 validation score for Advisor rightsizing recommendations. It works by:

1. Receiving Advisor's `targetSku` suggestion (e.g., "Standard_D8s_v5 → Standard_D4s_v5")
2. Calling `Get-AzComputeResourceSku` to look up the target SKU's capabilities
3. Validating 6 constraint dimensions against observed metrics:

| Constraint | SKU Capability Checked | Impact on FitScore |
|---|---|---|
| Data disk count | `MaxDataDiskCount` | **Drops to 1** if current disks > target max |
| NIC count | `MaxNetworkInterfaces` | **Drops to 1** if current NICs > target max |
| Uncached disk IOPS | `UncachedDiskIOPS` | **-1** if observed P99 IOPS ≥ target cap |
| Uncached disk throughput | `UncachedDiskBytesPerSecond` | **-1** if observed P99 MiBps ≥ target cap |
| CPU utilization | Perf table (P99) | **-0.5** if P99 CPU% ≥ threshold (default: 30%) |
| Memory utilization | Perf table (P99) | **-0.5** if P99 Memory% ≥ threshold (default: 50%) |
| Network throughput | Perf table (P99) | **-0.1** if P99 Mbps ≥ threshold (default: 750 Mbps) |

A FitScore of 5 = safe to resize. A FitScore of 1 = hard constraint violation, do not resize.

---

## 3. Why AOE Is More Like SRE Than FinOps

### 3.1 The FinOps Framework definition

The [FinOps Foundation](https://www.finops.org/framework/) defines FinOps as an operational framework for managing cloud financial management. The core capabilities are:

- **Inform** — cost visibility, allocation, showback/chargeback
- **Optimize** — rate optimization (reservations, savings plans), usage optimization (rightsizing)
- **Operate** — budgets, forecasting, anomaly detection, policy governance

AOE touches "usage optimization" at the surface level (it produces savings estimates), but its **mechanism** is entirely infrastructure operations.

### 3.2 What AOE actually operates on

| What AOE Analyzes | FinOps Concern? | SRE Concern? |
|---|---|---|
| P99 CPU percentile over 7 days | ❌ | ✅ Capacity planning |
| P99 memory utilization | ❌ | ✅ Performance monitoring |
| P99 disk IOPS and throughput | ❌ | ✅ Storage performance |
| P99 network bandwidth | ❌ | ✅ Network capacity |
| VM power state (deallocated/stopped) | Partially (cost) | ✅ Infrastructure hygiene |
| SKU constraint validation (disk count, NIC count) | ❌ | ✅ Workload compatibility |
| `Get-AzComputeResourceSku` capabilities | ❌ | ✅ Infrastructure planning |
| NSG rule analysis | ❌ | ✅ Security operations |
| RBAC assignment review | ❌ | ✅ Access governance |
| Azure Policy compliance | ❌ | ✅ Compliance operations |
| App registration credential expiry | ❌ | ✅ Identity operations |
| Load balancer backend pool emptiness | ❌ | ✅ Network hygiene |
| VNet subnet utilization | ❌ | ✅ Network planning |
| Availability set/zone membership | ❌ | ✅ Reliability engineering |

**14 of 14 data dimensions are SRE concerns. Only 1 (VM power state) partially overlaps with FinOps.**

### 3.3 Who operates AOE?

A FinOps practitioner's daily workflow:

- Reviews cost dashboards and anomaly alerts
- Allocates costs to teams via tags and subscriptions
- Tracks budget adherence and forecasts
- Negotiates commitment discounts (reservations, savings plans)
- Reports unit economics to leadership

An SRE/Platform Engineer's daily workflow:

- Monitors resource utilization and performance metrics
- Validates infrastructure change impact
- Reviews idle/orphaned resources for cleanup
- Ensures high availability and compliance
- Manages identity, RBAC, and policy posture

**AOE is a tool for the second person.** A FinOps practitioner would consume AOE's *savings estimates* as input, but would never configure P99 percentile thresholds, validate NIC count constraints, or review NSG rules.

### 3.4 Data pipeline comparison

| Dimension | FinOps Hub (FinOps) | AOE (SRE) |
|---|---|---|
| Primary data | Cost Management exports (FOCUS format) | Resource Graph, Azure Monitor metrics, Advisor |
| Data format | FOCUS 1.0-1.3 (standardized cost schema) | 15+ custom schemas (one per resource type) |
| Ingestion path | Blob → ADF/Fabric → ADX/Eventhouse | Blob CSV → Log Analytics custom tables |
| Query language | KQL over FOCUS columns | KQL over infrastructure properties |
| Output | Cost dashboards, allocation reports | Optimization recommendations, FitScore |
| Who reads it | FinOps team, leadership | SRE team, platform engineering |
| Actions taken | Adjust budgets, buy commitments, tag resources | Resize VMs, delete disks, consolidate networks |

### 3.5 The cost savings output is a byproduct, not the purpose

AOE calculates savings estimates for each recommendation. But the *purpose* of each recommendation is infrastructure optimization:

- "Delete this VM" → **infrastructure cleanup** (savings is the justification)
- "Downgrade disk to Standard HDD" → **storage optimization** (savings is the metric)
- "Resize VM from D8s to D4s" → **capacity rightsizing** (savings is the benefit)
- "Remove empty load balancer" → **network hygiene** (savings is minimal but real)
- "Fix expiring credentials" → **security operations** (no savings at all)

If you removed the savings calculations entirely, AOE would still be useful as an infrastructure optimization tool. If you removed the infrastructure analysis, the savings calculations would have no basis.

### 3.6 AOE's limitations reinforce the SRE characterization

| Limitation | Why This Is an SRE Problem |
|---|---|
| Uses P99 percentile — doesn't understand workload patterns (burst vs steady-state) | SRE capacity planning requires pattern awareness |
| Can't propose alternative SKUs when fit check fails | SRE needs to find the right infrastructure, not just reject wrong ones |
| 7-day batch lookback misses monthly/seasonal patterns | SRE capacity planning operates on longer horizons |
| No awareness of workload type (SQL memory ≠ web app memory) | SRE must understand application characteristics |
| FitScore is static arithmetic, not adaptive | Modern SRE uses ML/AI for anomaly detection |

Every limitation is a gap in **SRE tooling**, not in **FinOps reporting**.

---

## 4. AOE → SRE Agent Migration Map

### Infrastructure eliminated

| AOE Component | Lines of Code | SRE Agent Replacement |
|---|---|---|
| 22 data collection runbooks | ~8,000 PS1 | **Eliminated** — agent queries APIs directly |
| 13 recommendation runbooks | ~6,000 PS1 | 5 subagent definitions (~200 lines YAML) |
| Ingestion runbooks | ~2,000 PS1 | **Eliminated** — no batch pipeline |
| Automation Account + schedules | Bicep + 50 variables | **Eliminated** — managed service |
| SQL Database + tables | SQL schema + init scripts | **Eliminated** — agent maintains state |
| Log Analytics custom tables | 15+ custom tables | **Eliminated** — agent queries Monitor directly |
| Storage account (20+ containers) | Blob lifecycle config | **Eliminated** — no intermediate storage |
| Power BI workbook | JSON dashboard | Teams/email reports + ticketing integration |
| **Total** | **~16,000 lines** | **~200 lines YAML + knowledge base docs** |

### Subagent mapping

| SRE Agent Subagent | AOE Runbooks Replaced | Schedule |
|---|---|---|
| **Compute Optimization Specialist** | `AdvisorCostAugmented`, `VMOptimizations`, `VMSSOptimizations`, `VMsHighAvailability` | Weekly Monday 6 AM |
| **Storage Optimization Specialist** | `UnattachedDisks`, `DiskOptimizations`, `StorageAccountOptimizations` | Weekly Monday 7 AM |
| **Network Optimization Specialist** | `UnusedLoadBalancers`, `UnusedAppGWs`, `VNetOptimizations` | Weekly Monday 8 AM |
| **PaaS Optimization Specialist** | `AppServiceOptimizations`, `SqlDbOptimizations` | Weekly Monday 9 AM |
| **Governance & Compliance Specialist** | `AADExpiringCredentials`, `ARMOptimizations`, `AdvisorAsIs` | Weekly Monday 10 AM |

### What carries forward

- ✅ **FitScore concept** — embedded in Compute subagent instructions as SKU validation logic
- ✅ **Threshold defaults** — CPU 30%, memory 50%, network 750 Mbps preserved in knowledge base
- ✅ **Recommendation categories** — same taxonomy, same scope
- ✅ **Savings estimates** — calculated per recommendation

### What improves

- 🆕 **Real-time data** — no 7-day stale batch, queries APIs on demand
- 🆕 **Workload pattern awareness** — AI understands burst vs steady-state vs batch
- 🆕 **Alternative SKU suggestions** — can iterate SKU catalog when fit check fails
- 🆕 **Incident integration** — recommendations can trigger PagerDuty/ServiceNow tickets automatically
- 🆕 **Natural language interaction** — ask questions about recommendations in the portal chat

---

## 5. Recommendation

| Action | Timing |
|---|---|
| ✅ Keep AOE in `microsoft/finops-toolkit` as-is | Now |
| ✅ Post community discussion/poll on GitHub | Now |
| ❌ Do NOT bring AOE into AVM | Decided |
| ❌ Do NOT build AOE test data generators | Decided |
| 📋 Track Azure SRE Agent GA milestone | Ongoing |
| 📋 File feature request on `microsoft/sre-agent` for optimization subagent samples | After community feedback |
| 📋 Contribute subagent YAML definitions to `microsoft/sre-agent/samples/` | After SRE Agent team greenlight |
| 📋 Publish migration guide: "AOE → SRE Agent Subagents" | After SRE Agent GA |
| 📋 Consider: Hub dashboard page for Advisor savings (FOCUS-native, no AOE needed) | Future |

---

## 6. References

- [Azure SRE Agent Overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview)
- [SRE Agent Subagent Builder](https://learn.microsoft.com/en-us/azure/sre-agent/subagent-builder-overview)
- [SRE Agent Subagent Scenarios](https://learn.microsoft.com/en-us/azure/sre-agent/subagent-builder-scenarios)
- [SRE Agent GitHub — microsoft/sre-agent](https://github.com/microsoft/sre-agent)
- [AOE Source — microsoft/finops-toolkit/src/optimization-engine](https://github.com/microsoft/finops-toolkit/tree/dev/src/optimization-engine)
- [FinOps Toolkit Discussion #1899 — What is the future of the FinOps Hub Toolkit?](https://github.com/microsoft/finops-toolkit/discussions/1899)
- [FinOps Foundation Framework](https://www.finops.org/framework/)
