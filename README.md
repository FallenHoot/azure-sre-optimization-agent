# Azure Optimization Subagents for SRE Agent

> **Replace ~16,000 lines of PowerShell with ~200 lines of YAML + knowledge base docs**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Status: PoC](https://img.shields.io/badge/Status-PoC-orange.svg)](#phased-delivery)

---

## What is this?

A collection of **Azure SRE Agent subagents** that port the [Azure Optimization Engine (AOE)](https://github.com/microsoft/finops-toolkit/tree/dev/src/optimization-engine) into the [Azure SRE Agent](https://learn.microsoft.com/en-us/azure/sre-agent/overview) platform.

Instead of 50 Azure resources, 35 PowerShell runbooks, and a SQL database, you get **YAML definitions + markdown knowledge base documents** that an AI agent uses to perform the same infrastructure optimization analysis in real-time.

## Why?

| Dimension | AOE (Current) | SRE Agent Subagents (This Project) |
|---|---|---|
| Data collection | 22 PowerShell runbooks → blob → LA | Agent queries APIs directly |
| Recommendation logic | 13 PowerShell runbooks with hardcoded rules | Subagent instructions + knowledge base |
| Infrastructure | ~50 Azure resources | 3 resources (App Insights, LA, MI) |
| Output | SQL DB + Power BI | Email, Teams, ServiceNow, PagerDuty |
| Intelligence | Static arithmetic (P99, thresholds) | AI-powered pattern analysis |

## What's included

### Subagents

| Subagent | Phase | AOE Runbooks Replaced |
|---|---|---|
| [Compute Optimization](subagents/compute-optimization/) | **Phase 1 (PoC)** | `AdvisorCostAugmented`, `VMOptimizations`, `VMSSOptimizations`, `VMsHighAvailability` |
| [Storage Optimization](subagents/storage-optimization/) | Phase 2 | `UnattachedDisks`, `DiskOptimizations`, `StorageAccountOptimizations` |
| [Network Optimization](subagents/network-optimization/) | Phase 2 | `UnusedLoadBalancers`, `UnusedAppGWs`, `VNetOptimizations` |
| [PaaS Optimization](subagents/paas-optimization/) | Phase 2 | `AppServiceOptimizations`, `SqlDbOptimizations` |
| [Governance & Compliance](subagents/governance-compliance/) | Phase 2 | `AADExpiringCredentials`, `ARMOptimizations`, `AdvisorAsIs` |
| [Orchestrator](subagents/orchestrator/) | Phase 2 | Cross-domain aggregation and reporting |

### Knowledge Base

| Document | Purpose |
|---|---|
| [FitScore-Methodology.md](knowledge-base/FitScore-Methodology.md) | Core FitScore algorithm (0–5 validation score) |
| [SKU-Constraint-Rules.md](knowledge-base/SKU-Constraint-Rules.md) | SKU capability validation rules |
| [Threshold-Defaults.md](knowledge-base/Threshold-Defaults.md) | Default metric thresholds |
| [Recommendation-Format.md](knowledge-base/Recommendation-Format.md) | Output schema for recommendations |
| [Savings-Estimation.md](knowledge-base/Savings-Estimation.md) | Pricing and savings calculation methods |
| [Severity-Classification.md](knowledge-base/Severity-Classification.md) | Alert severity rules |
| [Resource-Graph-Queries.md](knowledge-base/Resource-Graph-Queries.md) | Pre-built Azure Resource Graph queries |
| [Metric-Collection-Guide.md](knowledge-base/Metric-Collection-Guide.md) | Azure Monitor query patterns |
| [Escalation-Criteria.md](knowledge-base/Escalation-Criteria.md) | Ticket and alert escalation rules |
| [Workload-Patterns.md](knowledge-base/Workload-Patterns.md) | AI-powered workload pattern detection (NEW) |

## Quick Start

### Prerequisites

- Azure subscription with [SRE Agent Preview](https://learn.microsoft.com/en-us/azure/sre-agent/overview) access
- Azure CLI installed (`az login`)
- Owner or User Access Administrator role (for RBAC setup)

### Deploy (Recommended — Bicep + PowerShell)

```powershell
# One command deploys Agent + Managed Identity + Log Analytics + App Insights + RBAC
.\scripts\deploy.ps1
```

### Deploy (Portal — Step-by-Step)

See [docs/DEPLOY-TO-SRE-AGENT.md](docs/DEPLOY-TO-SRE-AGENT.md) for a field-by-field portal walkthrough.

### Full Deployment Options

See [docs/deployment-guide.md](docs/deployment-guide.md) to choose the right path.

## Repository Structure

```
├── subagents/                      # 6 specialist subagent YAML configs
│   ├── compute-optimization/       #   VM rightsizing, FitScore, idle detection
│   ├── storage-optimization/       #   Orphan disks, tier analysis
│   ├── network-optimization/       #   Unused LBs, orphan IPs/NICs/NSGs
│   ├── paas-optimization/          #   App Service, SQL DB optimization
│   ├── governance-compliance/      #   Advisor, credentials, compliance
│   └── orchestrator/               #   Cross-domain aggregation
├── knowledge-base/                 # 10 markdown docs (agent's reference material)
├── infra/                          # Bicep IaC templates
│   ├── main.bicep                  #   Subscription-scoped entry point
│   ├── modules/                    #   Agent resources + RBAC
│   └── demo/                       #   Demo workloads for testing
├── scripts/                        # Deployment and RBAC automation
│   ├── deploy.ps1                  #   Main deployment script
│   ├── deploy-subagents.ps1        #   Subagent creation automation
│   ├── setup-rbac.sh               #   RBAC role assignments
│   └── validate-access.sh          #   Access validation
├── tests/                          # Simulation, FitScore tests, scenarios
├── docs/                           # Guides, architecture, comparison
└── subagent-registry.yaml          # Root index of all subagents
```

## The FitScore

The most valuable piece ported from AOE is the **FitScore** — a 0–5 validation score for VM rightsizing recommendations:

```
Score 5.0 — ✅ Safe to resize (all constraints pass)
Score 4.x — ✅ Likely safe (minor soft constraints)
Score 3.x — ⚠️  Caution (review before proceeding)
Score 2.x — ❌ Risky (significant constraint pressure)
Score 1.x — 🛑 Do NOT resize (hard constraint violation)
```

FitScore validates 7 dimensions: data disk count, NIC count, uncached disk IOPS, uncached disk throughput, CPU utilization, memory utilization, and network throughput.

**New capability beyond AOE:** When FitScore fails, our subagent searches the SKU catalog for alternative sizes that *do* pass validation.

## Acting on Findings

After the agent generates a report, you choose how to remediate:

| Approach | How | Best for |
|---|---|---|
| **Direct fix** | Ask the agent: *"Resize vm-oversized-v3 to D2s_v5"* — agent executes via `RunAzCliWriteCommands` | Dev/test, demo environments |
| **Script generation** | Ask: *"Generate the CLI commands to fix all findings"* — agent outputs a reviewable script | Production with manual change control |
| **IaC generation** | Ask: *"Generate Bicep to remediate these findings"* — agent produces IaC you merge via PR | Regulated environments, GitOps workflows |

**Recommended for production:** Use IaC generation with a separate infrastructure repo. The agent scans and reports in this repo; remediation PRs go to your team's infra repo where they follow normal change management (PR review → approval → CI/CD deploy). This keeps "how the agent thinks" separate from "what the agent changes."

```
┌──────────────────────┐     ┌────────────────────────┐
│  This repo           │     │  Your infra repo       │
│  (agent brain)       │     │  (workload resources)  │
│                      │     │                        │
│  subagents/          │────▶│  Agent opens PR with   │
│  knowledge-base/     │     │  Bicep/Terraform fix   │
│  scripts/            │     │  + FitScore rationale  │
└──────────────────────┘     └────────────────────────┘
```

## Phased Delivery

| Phase | Scope | Status |
|---|---|---|
| **Phase 1** | Compute PoC (FitScore + idle detection) | ✅ Complete |
| **Phase 2** | Storage + Network + PaaS + Governance + Orchestrator | ✅ Complete |
| **Phase 3** | IaC, Demo Environment, Testing Framework | ✅ Complete |
| **Phase 4** | Community contribution | 🔄 In progress |

## Contributing

We welcome contributions! See [docs/contributing.md](docs/contributing.md) for how to:

- Add a new subagent or knowledge base document
- Improve FitScore scoring or thresholds
- Extend test coverage
- Fix bugs or improve documentation

### Quick Contribution Paths

| What to change | Where to look |
|---|---|
| Add/improve a subagent | `subagents/<name>/subagent.yaml` |
| Update threshold defaults | `knowledge-base/Threshold-Defaults.md` |
| Add a new KQL query | `knowledge-base/Resource-Graph-Queries.md` |
| Improve FitScore logic | `knowledge-base/FitScore-Methodology.md` |
| Fix IaC | `infra/main.bicep` or `infra/modules/` |

## Attribution

This project builds on the [Azure Optimization Engine](https://github.com/microsoft/finops-toolkit/tree/dev/src/optimization-engine) created by **Hélder Pinto** ([@helderpinto](https://github.com/helderpinto)) as part of the [FinOps Toolkit](https://github.com/microsoft/finops-toolkit). The FitScore methodology, threshold defaults, and recommendation categories are derived from AOE with the creator's knowledge and support.

## License

[MIT](LICENSE)

## References

- [Azure SRE Agent Overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview)
- [SRE Agent Subagent Builder](https://learn.microsoft.com/en-us/azure/sre-agent/subagent-builder-overview)
- [AOE Source Code](https://github.com/microsoft/finops-toolkit/tree/dev/src/optimization-engine)
- [FinOps Toolkit](https://github.com/microsoft/finops-toolkit)
