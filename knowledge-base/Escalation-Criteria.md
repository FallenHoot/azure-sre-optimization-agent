# Escalation Criteria

## Purpose

This document defines when and how to escalate optimization findings — from silent logging to immediate alerting. The goal is to ensure Critical findings receive immediate attention, while lower-severity findings are batched into reports to avoid alert fatigue.

---

## Escalation Levels

| Level | Trigger | Channels | Response Time |
|---|---|---|---|
| **Log Only** | Low severity, informational findings | Written to scan results database/storage only | N/A — reviewed in weekly report |
| **Email (Weekly Report)** | Medium and Low severity | Included in weekly optimization digest email | Reviewed weekly |
| **Email + Ticket** | High severity | Immediate email notification + ServiceNow change request or PagerDuty alert | Within 1 week |
| **Immediate Alert** | Critical severity | Teams adaptive card + urgent ServiceNow incident + PagerDuty alert | Within 24 hours |

---

## Level 1: Log Only

### When to Use
- **Low severity** findings (savings < $25, informational)
- HA configuration gaps
- Outdated API versions
- Missing recommended tags
- Resources already tagged with `aoe:severity=suppress`

### What Happens
- Finding is written to the recommendation output store (Azure Storage / Cosmos DB)
- Finding is included in the weekly report summary statistics
- No individual notification is sent

---

## Level 2: Email (Weekly Report)

### When to Use
- **Medium severity** findings
- **Low severity** findings (included for completeness)
- Aggregate summary of all findings from the weekly scan

### Email Distribution
- Sent to a configurable distribution list per subscription or resource group
- Default: SRE team distribution list
- Override via tag `aoe:notifyEmail` on subscription or resource group

### Email Format
See [Recommendation-Format.md](Recommendation-Format.md) for the full email template structure:
1. Executive Summary
2. By-Category Breakdown
3. Top 10 by Savings
4. Critical Findings (if any)
5. Trend vs Previous Week

### Timing
- Sent once per week, after the weekly scan completes
- Default: Monday 8:00 AM UTC (configurable)

---

## Level 3: Email + Ticket

### When to Use
- **High severity** findings:
  - FitScore ≥ 4.0 with monthly savings > $100
  - Deallocated VMs older than 30 days
  - Credentials expiring within 7 days
  - Unattached Premium disks > $50/mo
  - Unused Application Gateways (always high cost)

### Email Notification
- Sent within 1 hour of scan completion
- Subject: `[AOE-High] {count} High-Severity Optimization Findings — {subscriptionName}`
- Body includes summary of High findings + links to full report
- Sent to: SRE team + resource group owners (if tagged with `aoe:owner`)

### ServiceNow Change Request

When auto-ticketing is enabled, create a ServiceNow Change Request with these fields:

| Field | Value |
|---|---|
| **Category** | Cloud Infrastructure |
| **Subcategory** | Cost Optimization |
| **Type** | Normal Change |
| **Urgency** | 2 - Medium |
| **Impact** | 3 - Low (cost optimization, not outage) |
| **Priority** | Calculated from Urgency + Impact |
| **Assignment Group** | Determined by resource group tag `aoe:assignmentGroup`, default: "Cloud SRE" |
| **Short Description** | `[AOE] {action} recommended for {resourceName} — ${monthlySavings}/mo savings` |
| **Description** | Full recommendation details including current state, target state, evidence, risk assessment |
| **Configuration Item** | Azure resource ID |
| **Planned Start Date** | Next available maintenance window |
| **Planned End Date** | Planned Start + 1 hour |
| **Change Risk** | Low (for resize/delete of non-production) or Medium (for production) |
| **Backout Plan** | `Resize back to {currentSku}` or `Restore from snapshot/backup` |
| **Custom Fields** | `aoe_recommendation_id`, `aoe_monthly_savings`, `aoe_fit_score` |

### ServiceNow API Integration

```
POST https://{instance}.service-now.com/api/now/table/change_request
Authorization: Bearer {token}
Content-Type: application/json

{
  "category": "Cloud Infrastructure",
  "subcategory": "Cost Optimization",
  "type": "normal",
  "urgency": "2",
  "impact": "3",
  "assignment_group": "{assignmentGroup}",
  "short_description": "[AOE] Resize recommended for webserver01 — $140.16/mo savings",
  "description": "...",
  "cmdb_ci": "{resourceId}",
  "u_aoe_recommendation_id": "{recommendationId}",
  "u_aoe_monthly_savings": "140.16",
  "u_aoe_fit_score": "4.5"
}
```

---

## Level 4: Immediate Alert

### When to Use
- **Critical severity** findings:
  - Stopped-not-deallocated VMs (paying for idle resources)
  - Expired credentials (security risk — past expiry date)
  - FitScore hard constraint violations on production resources

### Microsoft Teams Webhook

Send an adaptive card to a Teams channel immediately upon finding:

**Webhook URL:** Configured per environment in the orchestrator configuration.

**Adaptive Card Template:**

```json
{
  "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
  "type": "AdaptiveCard",
  "version": "1.4",
  "body": [
    {
      "type": "TextBlock",
      "text": "🚨 Critical Optimization Finding",
      "weight": "Bolder",
      "size": "Large",
      "color": "Attention"
    },
    {
      "type": "FactSet",
      "facts": [
        { "title": "Resource", "value": "{resourceName}" },
        { "title": "Resource Group", "value": "{resourceGroup}" },
        { "title": "Subscription", "value": "{subscriptionName}" },
        { "title": "Finding", "value": "{subcategory}" },
        { "title": "Monthly Cost Impact", "value": "${monthlyCost}" },
        { "title": "Risk", "value": "{riskAssessment}" }
      ]
    },
    {
      "type": "TextBlock",
      "text": "{recommendation.description}",
      "wrap": true
    }
  ],
  "actions": [
    {
      "type": "Action.OpenUrl",
      "title": "View in Azure Portal",
      "url": "https://portal.azure.com/#@{tenantId}/resource{resourceId}"
    },
    {
      "type": "Action.OpenUrl",
      "title": "View Ticket",
      "url": "{ticketUrl}"
    }
  ]
}
```

### PagerDuty Integration

**When to trigger:** Critical findings only.

**Severity mapping:**

| AOE Severity | PagerDuty Severity |
|---|---|
| Critical | `critical` |
| High | `error` |
| Medium | Not sent to PagerDuty |
| Low | Not sent to PagerDuty |

**PagerDuty Events API v2:**

```
POST https://events.pagerduty.com/v2/enqueue

{
  "routing_key": "{integration_key}",
  "event_action": "trigger",
  "dedup_key": "aoe-{resourceId}-{subcategory}",
  "payload": {
    "summary": "[AOE Critical] {subcategory}: {resourceName} in {subscriptionName}",
    "source": "azure-optimization-engine",
    "severity": "critical",
    "component": "{resourceGroup}",
    "group": "{subscriptionName}",
    "class": "{category}",
    "custom_details": {
      "resource_id": "{resourceId}",
      "monthly_cost": "{monthlyCost}",
      "recommendation": "{recommendation.description}",
      "fit_score": "{fitScore.score}",
      "risk_assessment": "{riskAssessment}"
    }
  },
  "links": [
    {
      "href": "https://portal.azure.com/#@{tenantId}/resource{resourceId}",
      "text": "View in Azure Portal"
    }
  ]
}
```

### ServiceNow Incident (Critical)

For Critical findings, create a ServiceNow **Incident** (not a Change Request):

| Field | Value |
|---|---|
| **Category** | Cloud Infrastructure |
| **Subcategory** | Cost Optimization — Critical |
| **Urgency** | 1 - High |
| **Impact** | 2 - Medium |
| **Priority** | Calculated (typically P2) |
| **Assignment Group** | Determined by tag or default "Cloud SRE — Urgent" |
| **Short Description** | `[AOE-CRITICAL] {subcategory}: {resourceName} — immediate action required` |
| **Description** | Full recommendation details |
| **State** | New |

---

## De-Duplication Rules

To prevent alert fatigue and duplicate tickets:

1. **Same resource + same finding type within 7 days:** Do NOT create a new ticket. Instead, add a work note to the existing ticket: `"AOE re-scan confirmed this finding is still active as of {timestamp}."`

2. **De-duplication key format:** `{resourceId}:{subcategory}`

3. **Check before creating:**
   - Query ServiceNow for open tickets with matching `aoe_recommendation_id` or `cmdb_ci` + `subcategory`
   - Query PagerDuty using `dedup_key`

4. **Escalation on persistence:** If the same Critical finding persists for 3 consecutive weekly scans (21 days), escalate the ticket urgency and add a note: `"This critical finding has persisted for {days} days without remediation."`

---

## Auto-Close Rules

If a finding is resolved between scans (e.g., VM deleted, disk attached, credential rotated):

1. **Detect resolution:** Compare current scan results with previous scan results. If a resource with an open ticket no longer appears in findings:
   - Verify the resource still exists (it may have been deleted)
   - If resource is deleted or the condition is resolved, auto-close the ticket

2. **ServiceNow auto-close:**
   - Update ticket state to "Resolved"
   - Add close note: `"AOE scan on {timestamp} confirmed this finding has been resolved. {resolution_detail}"`
   - Set resolution code: `"Resolved by Change"` or `"Resolved by Deletion"`

3. **PagerDuty auto-resolve:**
   ```json
   {
     "routing_key": "{integration_key}",
     "event_action": "resolve",
     "dedup_key": "aoe-{resourceId}-{subcategory}"
   }
   ```

4. **Teams notification:** Send a "Resolved" adaptive card to the same channel:
   ```
   ✅ Resolved: {subcategory} for {resourceName} — finding no longer active.
   ```

---

## Configuration

All escalation settings are configured in the orchestrator's configuration file:

```yaml
escalation:
  email:
    enabled: true
    weeklyReportDay: Monday
    weeklyReportTimeUtc: "08:00"
    defaultRecipients:
      - sre-team@company.com
    perSubscription:
      "sub-id-1":
        recipients:
          - team-a@company.com

  serviceNow:
    enabled: true
    instanceUrl: "https://company.service-now.com"
    authType: "oauth2"
    defaultAssignmentGroup: "Cloud SRE"
    autoTicketSeverities:
      - Critical
      - High

  pagerDuty:
    enabled: true
    integrationKey: "{from-key-vault}"
    triggerSeverities:
      - Critical

  teams:
    enabled: true
    webhookUrl: "{from-key-vault}"
    alertSeverities:
      - Critical

  deduplication:
    windowDays: 7
    escalateAfterScans: 3

  autoClose:
    enabled: true
    resolutionCheckEnabled: true
```

---

## Escalation Decision Flowchart

```
Finding generated
    ↓
Is severity Critical?
    YES → Immediate Alert (Teams + PagerDuty + ServiceNow Incident)
    NO ↓
Is severity High?
    YES → Check de-duplication (open ticket exists?)
        YES → Add work note to existing ticket
        NO → Create ServiceNow Change Request + Send email
    NO ↓
Is severity Medium?
    YES → Include in weekly report email
    NO ↓
Is severity Low?
    YES → Log only + include in weekly report
```

---

## Scan Health Escalation (from Action Trails)

In addition to resource-level finding escalation, the orchestrator monitors
**scan health** using data from specialist action trails. These escalations are
based on the failure categories defined in **Failure-Taxonomy.md**.

### Trend-Aware Escalation Rules

| Pattern | Threshold | Escalation Level | Action |
|---|---|---|---|
| Same resource `DATA_MISSING` for 3+ consecutive scans | 3 weeks | High | "AMA deployment needed for {resource}" — include in executive summary |
| Same subscription `AUTH_EXPIRED` for 2+ consecutive scans | 2 weeks | Critical | "RBAC misconfiguration — scan blocked for {subscription}" — immediate alert |
| Specialist hits `BUDGET_EXCEEDED` for 2+ consecutive scans | 2 weeks | High | "Budget limits may need adjustment for {specialist}" — flag in platform health |
| >20% of resources in a domain hit `TRANSIENT` failures | Single scan | Medium | "Azure API throttling detected — consider staggering scans" — include in weekly report |
| >10% of resources hit `PERMANENT` failures | Single scan | Medium | "Possible infrastructure drift — resources may have been deleted since discovery" |
| Specialist scan outcome = `FAILED` | Single scan | High | "Specialist scan failed — manual investigation required" — create ticket |

### Platform Health Section in Executive Summary

The orchestrator includes a **Platform Health Summary** section in every
executive summary, derived from action trails:

```
## Platform Health Summary

### Scan Completion
| Specialist | Outcome | Tool Calls | Duration | Failures |
|---|---|---|---|---|
| Compute | COMPLETE | 87/200 (44%) | 32/55 min (58%) | 2 |
| Storage | COMPLETE | 62/200 (31%) | 18/55 min (33%) | 0 |
| Network | PARTIAL | 150/150 (100%) ⚠️ | 55/55 min (100%) ⚠️ | 5 |
| PaaS | COMPLETE | 45/200 (23%) | 12/55 min (22%) | 1 |
| Governance | COMPLETE | 98/150 (65%) | 40/55 min (73%) | 3 |

### Failure Summary
| Category | Count | Impact |
|---|---|---|
| DATA_MISSING | 8 | FitScore confidence reduced on 8 VMs (no AMA) |
| TRANSIENT | 3 | 3 resources retried successfully |
| TIMEOUT | 2 | 2 resources skipped — data gap in report |

### Trend Alerts
- ⚠️ vm-web-01: DATA_MISSING for 4 consecutive scans → AMA deployment needed
- ⚠️ Network specialist: budget exceeded 2 consecutive scans → review limits
```
