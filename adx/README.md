# SRE Optimization Engine — ADX Dashboard (Community Proposal)

> **Status:** 🟡 Proposal — seeking community feedback before implementation
> **Date:** February 16, 2026

## Overview

This folder contains everything needed to port the SRE Optimization Engine output
into an **Azure Data Explorer (ADX) dashboard** — designed to work alongside the
existing [FinOps Toolkit Hub](https://learn.microsoft.com/cloud-computing/finops/toolkit/hubs/finops-hubs-overview).

The idea: the SRE Agent runs weekly optimization scans (compute, storage, network,
PaaS, governance). Today, results live in chat and persisted knowledge documents.
By writing scan results into ADX, we unlock:

- **Historical trend tracking** — savings found vs. savings realized over time
- **Executive dashboards** — visual summaries without opening the SRE Agent portal
- **Cross-reference with FOCUS cost data** — join recommendations with actual spend
  from the FinOps Hub's `Costs` function
- **Team-wide visibility** — dashboards accessible to anyone with ADX Viewer access

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                  Existing FinOps Hub ADX Cluster                │
│                                                                 │
│  ┌──────────────┐  ┌──────────────────┐  ┌───────────────────┐ │
│  │ Hub database  │  │ Ingestion database│  │ SREOptimization  │ │
│  │ (FOCUS data)  │  │ (raw cost data)   │  │ (NEW database)   │ │
│  │              │  │                   │  │                  │ │
│  │ • Costs()    │  │ • Costs_raw       │  │ • Scans          │ │
│  │ • Prices()   │  │ • Costs_final_*   │  │ • Recommendations│ │
│  │              │  │ • PricingUnits     │  │ • SavingsTracking│ │
│  │              │  │ • Regions          │  │ • ResourceSnaps  │ │
│  │              │  │ • Services         │  │ • AgentMetrics   │ │
│  └──────┬───────┘  └──────────────────┘  └──────┬────────────┘ │
│         │              READ ONLY                  │ READ/WRITE  │
│         └──────────────────┬──────────────────────┘             │
│                            │                                    │
└────────────────────────────┼────────────────────────────────────┘
                             │
              ┌──────────────┼──────────────────┐
              │              │                   │
        ┌─────▼─────┐ ┌─────▼──────┐ ┌──────────▼──────────┐
        │ ADX       │ │ SRE Agent  │ │ Power BI (optional) │
        │ Dashboard │ │ Kusto Tool │ │ KQL connector       │
        └───────────┘ └────────────┘ └─────────────────────┘
```

## What's in this folder

| File | Purpose |
|------|---------|
| [README.md](README.md) | This file — overview and community proposal |
| [schema.kql](schema.kql) | KQL commands to create the `SREOptimization` database tables, functions, and ingestion mappings |
| [queries.kql](queries.kql) | Sample KQL queries for each dashboard page |
| [dashboard-pages.md](dashboard-pages.md) | Dashboard page layouts and tile specifications |
| [setup-guide.md](setup-guide.md) | Step-by-step instructions to deploy against your FinOps Hub |

## Why use the existing FinOps Hub ADX cluster?

| Option | Cost | Complexity | Recommendation |
|--------|------|------------|----------------|
| **A: Add database to existing FinOps Hub ADX** | $0 extra (uses existing cluster) | Low — just create a database | ✅ **Recommended** |
| B: Separate ADX cluster | +$120/mo minimum | High — new resource to manage | ❌ Overkill |
| C: Log Analytics only | Variable | Medium — limited KQL join capabilities | ❌ Limited |

The FinOps Hub already runs a Dev/Basic ADX cluster (~$120/mo). Adding a database
to the same cluster costs nothing extra. You get instant access to the FOCUS cost
data in the `Hub` database for cross-referencing.

## FOCUS alignment

The FinOps Hub stores cost data in [FOCUS v1.0](https://focus.finops.org/) format.
Our `SREOptimization` tables use **matching column names** where applicable
(e.g., `ResourceId`, `ResourceName`, `SubAccountName`, `ServiceCategory`) so you
can JOIN directly:

```kusto
// Example: Join SRE recommendations with actual FOCUS cost data
SREOptimization.Recommendations
| where ScanDate == ago(7d)
| join kind=leftouter (
    Hub.Costs
    | where ChargePeriodStart >= ago(30d)
    | summarize MonthlyCost = sum(EffectiveCost) by ResourceId
) on ResourceId
| project ResourceName, Recommendation, FitScore, EstimatedSavingsMonthly, ActualMonthlyCost = MonthlyCost
```

## Community question

> **Would an ADX dashboard for SRE optimization findings be useful to your team?**
>
> If so, what pages/visualizations would you want?
>
> - [ ] Optimization overview (total savings, recommendations by priority)
> - [ ] Savings trend (projected vs. realized over time)
> - [ ] Resource health (idle, orphaned, untagged resources)
> - [ ] Compute deep-dive (FitScore history, SKU migration tracking)
> - [ ] Cost correlation (recommendations × actual FOCUS spend)
> - [ ] Compliance posture (governance findings over time)
> - [ ] Other: _______________

Please open an issue or discussion with your feedback.

## Prerequisites

- FinOps Hub deployed with Azure Data Explorer ([setup guide](https://learn.microsoft.com/cloud-computing/finops/toolkit/hubs/deploy))
- SRE Agent managed identity granted `Database Viewer` on Hub & Ingestion databases
- SRE Agent managed identity granted `Database Admin` on SREOptimization database
- SRE Agent Kusto Tool configured to connect to the ADX cluster

## Credits

- [FinOps Toolkit](https://github.com/microsoft/finops-toolkit) by Microsoft
- [FOCUS specification](https://focus.finops.org/) by FinOps Foundation
- [Azure SRE Agent](https://learn.microsoft.com/azure/sre-agent/overview)
- Azure Optimization Engine by [@helderpinto](https://github.com/helderpinto)
