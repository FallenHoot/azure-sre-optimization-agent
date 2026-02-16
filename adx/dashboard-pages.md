# SRE Optimization Engine — ADX Dashboard Page Specifications

> **Status:** 🟡 Proposal — page layouts for community review

## Dashboard overview

| Page | Purpose | Primary audience | Refresh |
|------|---------|------------------|---------|
| 1. Optimization Overview | Executive summary of all findings | Leadership / FinOps | After each scan |
| 2. Savings Trend | Historical projected vs. realized savings | FinOps / Finance | Weekly |
| 3. Cost Correlation | Cross-reference findings with FOCUS cost data | FinOps | Weekly |
| 4. Compute Deep-Dive | FitScore analysis, SKU migration, Spot | SRE / Infra | After compute scan |
| 5. Resource Health | Idle, orphaned, untagged resource inventory | SRE / Platform | After any scan |
| 6. Compliance Posture | Governance findings trend, credential expiry | Security / Compliance | After governance scan |
| 7. Agent Operations | Agent health, AAU, scan success rate | Platform Engineering | Daily |

---

## Page 1: Optimization Overview

### Layout (3-column top row, 2-column body)

```
┌─────────────────┬─────────────────┬─────────────────┐
│  Total Savings   │  Findings Count │  Last Scan       │
│  $X,XXX/mo ↑↓   │  C:X H:X M:X L:X│  2h ago ✅/⚠️    │
├─────────────────┴─────────────────┴─────────────────┤
│                                                      │
│  [Donut] Savings by Domain      [Bar] Top Categories │
│  compute | storage | network    rightsizing | idle    │
│  paas | governance              orphan | tier | ...   │
│                                                      │
├──────────────────────────────────────────────────────┤
│  [Table] Top 10 Savings Opportunities                │
│  Resource | Domain | Current→Target | FitScore | $/mo│
└──────────────────────────────────────────────────────┘
```

### Tiles

| # | Tile | Type | Size | Query ref | Notes |
|---|------|------|------|-----------|-------|
| 1 | Total Monthly Savings | Stat | 1×1 | 1.1 | Green if > $0, with trend arrow |
| 2 | Findings by Severity | Stat (multi) | 1×1 | 1.1 | Critical=red, High=orange, Med=yellow, Low=blue |
| 3 | Last Scan Status | Stat | 1×1 | 1.4 | Show most recent scan time + status icon |
| 4 | Savings by Domain | Donut chart | 2×2 | 1.1 (domain) | Interactive — click to filter page |
| 5 | Recommendations by Category | Stacked bar | 2×2 | 1.2 | X=category, Y=count, color=domain |
| 6 | Top 10 Opportunities | Table | 4×2 | 1.3 | Sortable, click-to-drill |
| 7 | Scan Health | Table | 4×1 | 1.4 | One row per domain, green/red status |

### Filters

- **Time range**: Last 7d / 30d / 90d / Custom
- **Domain**: All / Compute / Storage / Network / PaaS / Governance
- **Severity**: All / Critical / High / Medium / Low
- **Subscription**: Dropdown (from `SubAccountName`)

---

## Page 2: Savings Trend

### Layout

```
┌──────────────────────────────────────────────────────┐
│  [Line] Projected Savings Over Time                  │
│  X=week, Y=USD, one line per domain (stacked area)   │
├──────────────────────────────────────────────────────┤
│  [Dual-axis Line] Projected vs. Realized Savings     │
│  Left Y=USD, Right Y=accuracy %                      │
├──────────────────┬───────────────────────────────────┤
│  [Funnel]         │  [Histogram]                     │
│  Implementation   │  Savings Accuracy Distribution   │
│  Status Counts    │  Buckets: <50% / 50-90% / etc.   │
└──────────────────┴───────────────────────────────────┘
```

### Tiles

| # | Tile | Type | Size | Query ref |
|---|------|------|------|-----------|
| 1 | Savings Over Time | Area chart | 4×2 | 2.1, 2.2 |
| 2 | Projected vs. Realized | Dual-axis line | 4×2 | 2.3 |
| 3 | Implementation Funnel | Funnel / bar | 2×2 | 2.4 |
| 4 | Accuracy Distribution | Histogram | 2×2 | 2.5 |

### Filters

- **Time range**: Last 30d / 90d / 6mo / 1yr
- **Domain**: All / individual

---

## Page 3: Cost Correlation

### Layout

```
┌──────────────────────────────────────────────────────┐
│  [Scatter] Subscription Cost vs. Savings Potential   │
│  X=total cost, Y=potential savings, size=finding cnt │
├──────────────────────────────────────────────────────┤
│  [Table] Recommendations + Actual FOCUS Cost         │
│  Resource | Est. Savings | Actual Cost | Savings %   │
├──────────────────────────────────────────────────────┤
│  [Table] Top Spenders WITHOUT Recommendations        │
│  Resource | Monthly Cost | "No findings"             │
└──────────────────────────────────────────────────────┘
```

### Tiles

| # | Tile | Type | Size | Query ref |
|---|------|------|------|-----------|
| 1 | Sub Cost vs. Savings | Scatter | 4×2 | 3.4 |
| 2 | Recs + Actual Cost | Table | 4×2 | 3.1 |
| 3 | Cost by ServiceCategory | Stacked bar | 2×2 | 3.3 |
| 4 | Top Spenders No Recs | Table | 4×1 | 3.2 |

### Filters

- **Time range**: Last 30d (FOCUS billing period)
- **ServiceCategory**: Compute / Storage / Networking / All
- **Subscription**: Dropdown

### Prerequisites

- `Hub` database must be accessible (cross-database query)
- FOCUS `Costs` function must be populated with recent billing data

---

## Page 4: Compute Deep-Dive

### Layout

```
┌──────────────────┬───────────────────────────────────┐
│  [Histogram]      │  [Table] SKU Migration Tracking   │
│  FitScore         │  Current Family → Target Family   │
│  Distribution     │  Count | Total Savings             │
├──────────────────┴───────────────────────────────────┤
│  [Table] All Compute Recommendations                 │
│  VM | Current→Target | FitScore | Savings | Workload │
├──────────────────────────────────────────────────────┤
│  [Detail Panel] FitScore Breakdown (click to expand) │
│  Dimension | Observed | Target Cap | Result | Impact │
├──────────────────┬───────────────────────────────────┤
│  [Table] Idle/    │  [Table] Spot VM Eligibility      │
│  Deallocated VMs  │  VM | Workload | Savings | Risk   │
└──────────────────┴───────────────────────────────────┘
```

### Tiles

| # | Tile | Type | Size | Query ref |
|---|------|------|------|-----------|
| 1 | FitScore Distribution | Histogram | 2×2 | 4.1 |
| 2 | SKU Migration | Table | 2×2 | 4.3 |
| 3 | All Compute Recs | Table | 4×2 | custom | Click row → tile 4 |
| 4 | FitScore Breakdown | Detail panel | 4×2 | 4.2 | Dynamic column from `FitScoreBreakdown` |
| 5 | Idle / Deallocated | Table | 2×2 | 4.5 |
| 6 | Spot Eligibility | Table | 2×2 | 4.6 |
| 7 | Gen Upgrades | Table | 4×1 | 4.4 |

### Filters

- **Location**: Region dropdown
- **Subscription**: Dropdown
- **FitScore range**: Slider 1.0 – 5.0

---

## Page 5: Resource Health

### Layout

```
┌──────────────────┬───────────────────────────────────┐
│  [Donut]          │  [Line] Resource Inventory Trend  │
│  Category         │  X=week, Y=count, by ResourceType │
│  Breakdown        │                                    │
├──────────────────┴───────────────────────────────────┤
│  [Table] Orphaned Resources                          │
│  Resource | Type | Location | Cost | Evidence        │
├──────────────────────────────────────────────────────┤
│  [Table] HA Gaps                                     │
│  Resource | Type | Current Config | Recommendation   │
├──────────────────┬───────────────────────────────────┤
│  [Bar] Power      │  [Table] Tagging Issues           │
│  State Breakdown  │  Resource | Tags | Recommendation │
└──────────────────┴───────────────────────────────────┘
```

### Tiles

| # | Tile | Type | Size | Query ref |
|---|------|------|------|-----------|
| 1 | Category Breakdown | Donut | 2×2 | 5.1 |
| 2 | Inventory Trend | Line | 2×2 | 5.5 |
| 3 | Orphaned Resources | Table | 4×2 | 5.2 |
| 4 | HA Gaps | Table | 4×1 | 5.4 |
| 5 | Power State | Bar | 2×2 | 5.6 |
| 6 | Tagging Issues | Table | 2×2 | 5.3 |

---

## Page 6: Compliance Posture

### Layout

```
┌──────────────────────────────────────────────────────┐
│  [Area] Governance Findings Trend                    │
│  X=week, Y=count, stacked by Category                │
├──────────────────┬───────────────────────────────────┤
│  [Bar] Findings   │  [Table] Credential Expiry        │
│  by Category      │  Resource | Severity | Expiry     │
├──────────────────┴───────────────────────────────────┤
│  [Bar] Tag Compliance Rate by Subscription           │
│  Sub Name | Total | Non-Compliant | Compliance %     │
└──────────────────────────────────────────────────────┘
```

### Tiles

| # | Tile | Type | Size | Query ref |
|---|------|------|------|-----------|
| 1 | Findings Trend | Area chart | 4×2 | 6.1 |
| 2 | By Category | Bar | 2×2 | 6.2 |
| 3 | Credential Expiry | Table | 2×2 | 6.3 |
| 4 | Tag Compliance | Table | 4×1 | 6.4 |

---

## Page 7: Agent Operations

### Layout

```
┌──────────────────┬──────────────────┬────────────────┐
│  Scans (30d)      │  Success Rate    │  Avg Duration  │
│  42 scans          │  95.2%           │  3m 22s        │
├──────────────────┴──────────────────┴────────────────┤
│  [Bar] Daily Scan Activity                           │
│  X=day, Y=scan count, color=status                   │
├──────────────────────────────────────────────────────┤
│  [Line] AAU Consumption Trend                        │
│  X=day, Y=AAU units consumed                         │
├──────────────────┬───────────────────────────────────┤
│  [Bar] Tool Call  │  [Line] API Error Rate            │
│  Distribution     │  X=day, Y=error count, by subagent│
└──────────────────┴───────────────────────────────────┘
```

### Tiles

| # | Tile | Type | Size | Query ref |
|---|------|------|------|-----------|
| 1 | Scan Count (30d) | Stat | 1×1 | 7.2 |
| 2 | Success Rate | Stat | 1×1 | 7.2 |
| 3 | Avg Duration | Stat | 1×1 | 7.1 |
| 4 | Daily Activity | Bar | 4×2 | 7.1 |
| 5 | AAU Trend | Line | 4×1 | 7.3 |
| 6 | Tool Calls | Bar | 2×2 | 7.4 |
| 7 | API Errors | Line | 2×2 | 7.5 |
| 8 | Data Gap Freq | Table | 4×1 | 7.6 |

---

## Color scheme

| Element | Color | Hex |
|---------|-------|-----|
| Compute domain | Blue | `#4A90D9` |
| Storage domain | Green | `#50C878` |
| Network domain | Purple | `#9B59B6` |
| PaaS domain | Orange | `#F39C12` |
| Governance domain | Teal | `#1ABC9C` |
| Critical severity | Red | `#E74C3C` |
| High severity | Orange | `#E67E22` |
| Medium severity | Yellow | `#F1C40F` |
| Low severity | Blue | `#3498DB` |
| FitScore ≥ 4.0 (safe) | Green | `#27AE60` |
| FitScore 3.0–3.9 (caution) | Amber | `#F39C12` |
| FitScore ≤ 2.9 (danger) | Red | `#E74C3C` |

## ADX dashboard export

All pages can be exported as a single ADX dashboard JSON file via:

1. **Azure Data Explorer** → Dashboards → Create
2. Add pages matching the layouts above
3. Pin queries from [queries.kql](queries.kql) to each tile
4. Set auto-refresh: 1 hour (or after scan completion)
5. Export → share JSON with the team

Alternatively, connect via **Power BI KQL connector** for organization-wide distribution.
