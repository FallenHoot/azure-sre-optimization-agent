# FinOps Toolkit AOE Issues — Analysis & Our Approach

Analysis of open [FinOps Toolkit Optimization Engine](https://github.com/microsoft/finops-toolkit/issues?q=is%3Aissue+is%3Aopen+label%3A%22Tool%3A+Optimization+Engine%22) issues and how the SRE Agent subagent approach addresses them.

> **Date:** February 15, 2026

---

## Actionable Issue: #1753 — Costs Ingestion Offset

**Issue:** [microsoft/finops-toolkit#1753](https://github.com/microsoft/finops-toolkit/issues/1753)
**Status:** Open · Good first issue 🏆 · Unassigned
**Filed by:** @helderpinto (Jul 8, 2025)

### Problem

AOE workbooks (Benefits Simulation, Reservations Potential, Reservations Usage, etc.) use a 30-day costs lookback period. However, AOE has a default 3-day ingestion offset (set as an Azure Automation variable that workbooks can't read). This means workbooks actually display results based on ~27 days of data, not 30.

### Proposed Solution (upstream)

Add a disclaimer or a costs offset parameter to affected workbooks so the offset is applied to the lookback window, giving users the full 30 days of cost data.

### How SRE Agent Subagents Avoid This

Our subagents **don't have this problem** because:

1. **No batch ingestion** — We query Azure APIs (Advisor, Resource Graph, Monitor, Retail Prices) directly at run time. There is no ingestion pipeline with a multi-day delay.
2. **No intermediate data store** — AOE writes to Log Analytics via blob storage, introducing the offset. Our subagents read and report in the same execution.
3. **Real-time cost data** — When we need pricing, we hit the [Azure Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices) directly, which reflects current list prices with no delay.

### Contribution Opportunity

This is tagged "Good first issue" and is unassigned. A PR to the FinOps Toolkit could:
- Add a `costIngestionOffsetDays` parameter (default 3) to affected workbook queries
- Adjust the `datetime(ago(...))` ranges to add the offset
- Add a disclaimer noting that cost data may be incomplete for the most recent 3 days

---

## Other Open AOE Issues

| # | Issue | Owner | Our Take |
|---|---|---|---|
| [#1602](https://github.com/microsoft/finops-toolkit/issues/1602) | Implement Azure Storage/ADX-based Power BI pages | @helderpinto | In progress. Not applicable to us — we don't use Power BI. |
| [#1412](https://github.com/microsoft/finops-toolkit/issues/1412) | Ingest ARG-based recommendations into ADX | @helderpinto | In code review. We do this via live ARG queries instead. |
| [#1407](https://github.com/microsoft/finops-toolkit/issues/1407) | Deal with duplicate recommendations ingestion | @helderpinto | Has merged PR #1512. We avoid this entirely — no ingestion, no duplicates. |
| [#1271](https://github.com/microsoft/finops-toolkit/issues/1271) | Document each Log Analytics table and runbooks | @helderpinto | In progress. Our `knowledge-base/` docs serve this purpose for the subagent approach. |
| [#1224](https://github.com/microsoft/finops-toolkit/issues/1224) | Add foundations for extensible cost optimization pipeline | @helderpinto | In progress. Our YAML-based subagent model is inherently extensible. |

---

## Key Architectural Advantage

Many of the open AOE issues stem from its **batch ingestion architecture**:

```
AOE:     Azure APIs → PowerShell runbooks → Blob → Log Analytics → Workbooks
         (delay: 3+ days for cost data, 24hrs for metrics)

SRE Agent: Azure APIs → Agent queries at run time → Report
           (delay: none — real-time)
```

By eliminating the ingestion pipeline, the SRE Agent subagents inherently avoid:
- ❌ Ingestion offset issues (#1753)
- ❌ Duplicate record problems (#1407)
- ❌ Stale data in workbooks
- ❌ Storage/ADX infrastructure costs (#1602)

This is one of the core architectural improvements documented in [docs/aoe-comparison.md](aoe-comparison.md).
