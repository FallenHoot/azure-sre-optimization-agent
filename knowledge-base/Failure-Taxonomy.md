# Failure Taxonomy

## Purpose

This document defines a standard classification for failures encountered during subagent scans. All specialists MUST classify every failure using these categories in their action trail documents. The orchestrator uses these categories to make retry/escalation decisions and track platform health trends.

---

## Failure Categories

| Category | Code | Description | Recovery Action | Retry? |
|---|---|---|---|---|
| **AUTH_EXPIRED** | `AUTH` | Authentication or authorization failure. Token expired, 401/403 from Azure API, insufficient RBAC permissions. | Skip resource, note gap. Do NOT retry (token won't self-heal within a scan). | No |
| **TRANSIENT** | `TRANS` | Temporary infrastructure issue. 429 throttling, network timeout, 503 service unavailable, intermittent Azure API errors. | Retry once after brief pause. If second attempt fails, classify as permanent for this scan. | Yes (1x) |
| **PERMANENT** | `PERM` | Non-recoverable error within this scan. Invalid subscription ID, resource not found (404), malformed query, unsupported resource type, deleted resource. | Log error, skip resource, continue to next. | No |
| **TIMEOUT** | `TIME` | Operation exceeded reasonable time limit. Metric query hung, activity log query too slow, pricing API unresponsive. 60+ seconds with no response. | Skip with "Data Gap" note, continue to next resource. | No |
| **DATA_MISSING** | `DATA` | Expected data is absent but the query itself succeeded. No AMA agent installed (no memory metrics), no Log Analytics workspace connected, metric retention expired, empty metric results for a running VM. | Reduce confidence in recommendation (e.g., lower FitScore), note gap in report. | No |
| **PARSE_ERROR** | `PARSE` | Tool returned data but it could not be interpreted. Unexpected JSON schema, missing expected fields, API version mismatch in response format. | Log raw response summary, skip resource, continue. | No |
| **BUDGET_EXCEEDED** | `BUDGET` | Agent hit a budget limit: max_tool_calls, max_duration_minutes, or max_consecutive_failures. | Stop gracefully. Save partial results. Note which limit was hit. | No |

---

## Classification Rules

1. **Always classify at the most specific level.** A 429 is `TRANSIENT`, not `PERMANENT`. A missing metric on a running VM is `DATA_MISSING`, not `PERMANENT`.

2. **Consecutive failures.** Track consecutive failures across all categories. If 3 consecutive tool calls fail (regardless of category), trigger the `BUDGET_EXCEEDED` stop condition.

3. **First failure wins.** If a resource fails with `TRANSIENT` on the first try and `TIMEOUT` on the retry, record both but classify the final outcome as `TIMEOUT`.

4. **Scope matters.** A failure scoped to one resource should not stop the scan. A failure scoped to an entire subscription (e.g., `AUTH_EXPIRED` for the subscription) should skip all resources in that subscription.

---

## Failure Severity Mapping

Failures themselves have severity (separate from recommendation severity):

| Failure Category | Scan Impact | Escalation |
|---|---|---|
| `AUTH_EXPIRED` | High — entire subscription may be blocked | Flag in action trail + orchestrator report. Suggests RBAC misconfiguration. |
| `TRANSIENT` | Low — usually affects 1-2 resources | Log only. Expected in normal operation. |
| `PERMANENT` | Medium — resource cannot be analyzed | Log in action trail. If >10% of resources hit PERMANENT, flag for review. |
| `TIMEOUT` | Medium — data gap in report | Log in action trail. If frequent, may indicate Log Analytics workspace issues. |
| `DATA_MISSING` | Medium — reduces recommendation confidence | Note in report per resource. If >50% of VMs lack memory metrics, flag as "AMA deployment needed" at High severity. |
| `PARSE_ERROR` | Low — rare, usually one-off | Log with raw response sample for debugging. |
| `BUDGET_EXCEEDED` | High — scan is incomplete | Always flag in action trail and report header. |

---

## Trend-Aware Escalation

The orchestrator tracks failure patterns across weekly scans:

| Pattern | Threshold | Escalation |
|---|---|---|
| Same resource has `DATA_MISSING` for 3+ consecutive scans | 3 weeks | Escalate to **High severity**: "AMA deployment needed for {resource}" |
| Same subscription has `AUTH_EXPIRED` for 2+ consecutive scans | 2 weeks | Escalate to **Critical**: "RBAC misconfiguration — scan blocked for {subscription}" |
| Any specialist exceeds `BUDGET_EXCEEDED` for 2+ consecutive scans | 2 weeks | Escalate to **High**: "Budget limits may need adjustment for {specialist}" |
| >20% of resources in a domain hit `TRANSIENT` failures | Single scan | Flag in orchestrator report: "Azure API throttling detected — consider staggering scans" |
| >10% of resources hit `PERMANENT` failures | Single scan | Flag: "Possible infrastructure drift — resources may have been deleted since discovery" |

---

## Action Trail Integration

Every failure MUST be recorded in the action trail document with:

```json
{
  "type": "failure",
  "resource_id": "/subscriptions/.../resourceGroups/.../providers/.../resourceName",
  "category": "DATA_MISSING",
  "detail": "No memory metrics available — AMA agent not installed",
  "tool": "RunAzCliReadCommands",
  "operation": "az monitor log-analytics query --analytics-query 'Perf | where ObjectName == Memory'",
  "impact": "FitScore calculated without memory dimension — reduced confidence",
  "retried": false,
  "consecutive_failure_count": 1
}
```

The orchestrator aggregates these across all specialists to produce the Platform Health section of the executive report.
