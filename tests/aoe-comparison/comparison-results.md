# AOE vs SRE Agent Comparison Results

**Test Date:** _YYYY-MM-DD_
**Test Subscription:** _subscription-name (subscription-id)_
**Resource Group:** _rg-sre-agent-test_
**AOE Version:** _v X.X_
**SRE Agent Version:** _PoC v0.1_

---

## Summary

| Metric | Value |
|---|---|
| Total resources in scope | |
| Resources flagged by AOE | |
| Resources flagged by SRE Agent | |
| Matched findings | |
| AOE-only findings | |
| SRE Agent-only findings | |
| FitScore delta (avg) | |
| Savings delta (avg) | |
| **Parity achieved?** | ✅ / ❌ |

---

## Detailed Comparison

### Compute Resources

| Resource | AOE Finding | SRE Agent Finding | AOE FitScore | SRE Agent FitScore | Delta | Notes |
|---|---|---|---|---|---|---|
| vm-oversized-test | | | | | | |
| vm-maxdisks-test | | | | | | |
| vm-deallocated-test | | | | | | |
| vm-stopped-test | | | | | | |
| vm-no-insights-test | | | | | | |

### Storage Resources

| Resource | AOE Finding | SRE Agent Finding | AOE FitScore | SRE Agent FitScore | Delta | Notes |
|---|---|---|---|---|---|---|
| disk-unattached-test | | | | | | |
| disk-overprovisioned-test | | | | | | |

### Network Resources

| Resource | AOE Finding | SRE Agent Finding | AOE FitScore | SRE Agent FitScore | Delta | Notes |
|---|---|---|---|---|---|---|
| lb-empty-test | | | | | | |
| nsg-orphaned-test | | | | | | |
| pip-orphaned-test | | | | | | |

### PaaS Resources

| Resource | AOE Finding | SRE Agent Finding | AOE FitScore | SRE Agent FitScore | Delta | Notes |
|---|---|---|---|---|---|---|
| asp-oversized-test | | | | | | |

---

## Savings Comparison

| Resource | AOE Estimated Savings ($/mo) | SRE Agent Estimated Savings ($/mo) | Delta ($/mo) | Delta (%) | Notes |
|---|---|---|---|---|---|
| vm-oversized-test | | | | | |
| vm-maxdisks-test | | | | | |
| vm-deallocated-test | | | | | |
| vm-stopped-test | | | | | |
| disk-unattached-test | | | | | |
| disk-overprovisioned-test | | | | | |
| asp-oversized-test | | | | | |
| **Total** | | | | | |

---

## SRE Agent Enhancements (Not Available in AOE)

| Enhancement | Observed? | Details |
|---|---|---|
| Alternative SKU search | ✅ / ❌ | |
| Missing metrics detection | ✅ / ❌ | |
| FitScore breakdown (soft/hard) | ✅ / ❌ | |
| Stopped-not-deallocated detection | ✅ / ❌ | |
| Actionable CLI commands in output | ✅ / ❌ | |
| Data quality scoring | ✅ / ❌ | |

---

## Discrepancies and Root Causes

| # | Resource | Discrepancy | Root Cause | Resolution |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |

---

## Conclusions

_Document overall findings, whether parity was achieved, and any action items._

1. **Parity:** _Was parity achieved? If not, what gaps remain?_
2. **Improvements:** _Which SRE Agent enhancements added measurable value?_
3. **Action items:** _What needs to be fixed or improved before production deployment?_

---

## Sign-Off

| Role | Name | Date | Approved? |
|---|---|---|---|
| Engineer | | | |
| Reviewer | | | |
