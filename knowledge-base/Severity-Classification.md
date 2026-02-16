# Severity Classification Rules

## Purpose

This document defines the rules for classifying optimization recommendations into severity levels: **Critical**, **High**, **Medium**, and **Low**. Consistent severity classification ensures that the most impactful and urgent findings receive appropriate attention and escalation.

---

## Severity Levels Overview

| Severity | Meaning | Response Time | Escalation |
|---|---|---|---|
| **Critical** | Immediate financial waste or security risk; requires urgent action | Within 24 hours | Auto-create ticket + immediate alert (Teams/PagerDuty) |
| **High** | Significant savings opportunity or approaching risk; action needed soon | Within 1 week | Email notification + optional ticket creation |
| **Medium** | Moderate savings or optimization opportunity | Within 2 weeks | Included in weekly report |
| **Low** | Minor optimization, informational, or best-practice improvement | At convenience | Included in weekly report only |

---

## Classification Rules Table

| Severity | Condition | Examples |
|---|---|---|
| **Critical** | Stopped-not-deallocated VMs (paying full compute for idle resource) | VM in "Stopped" power state (not "Deallocated") |
| **Critical** | Expired credentials (security risk — past expiry date) | App registration with client secret past expiry |
| **Critical** | FitScore hard constraint violations on **production** resources | Resizing recommendation that violates disk count or accelerated networking constraint, applied to a resource tagged `environment:production` |
| **High** | FitScore ≥ 4.0 AND monthly savings > $100 | VM rightsizing from D8s_v3 to D4s_v3 saving $140/mo with FitScore 4.5 |
| **High** | Deallocated VMs older than 30 days | VM deallocated for 45 days with attached disks costing $50/mo |
| **High** | Credentials expiring within 7 days | App registration secret expires in 5 days |
| **High** | Unattached managed disks (Premium tier, > $50/mo) | P30 Premium disk unattached for 14 days at $135/mo |
| **Medium** | FitScore 3.0–3.9 (viable but not ideal recommendation) | VM resize recommendation with FitScore 3.5 due to moderate memory pressure |
| **Medium** | Monthly savings $25–$100 | Resize saving $67/mo |
| **Medium** | Deallocated VMs 15–30 days | VM deallocated for 22 days |
| **Medium** | Credentials expiring in 7–30 days | App secret expires in 18 days |
| **Medium** | Unused network resources (load balancers, app gateways, public IPs) | Standard LB with zero backends at $18/mo |
| **Medium** | Aged snapshots (past threshold) | Snapshot 120 days old, 500 GB |
| **Low** | FitScore ≥ 4.0 but savings < $25 | Resize saving $15/mo — correct but low impact |
| **Low** | HA configuration gaps | VM not in availability set or zone |
| **Low** | Outdated API versions | Resource deployed with API version > 1 year old |
| **Low** | Informational Azure Advisor recommendations | Advisor "Impact: Low" suggestions |
| **Low** | Unattached Standard-tier disks < $10/mo | E10 StandardSSD disk at $7.68/mo |
| **Low** | Storage accounts with no lifecycle policy | Hot-tier storage with no automated tiering |

---

## Per-Category Severity Mapping

### Compute Optimization

| Finding Type | Critical | High | Medium | Low |
|---|---|---|---|---|
| Stopped-Not-Deallocated VM | ✅ Always | — | — | — |
| VM Rightsizing | — | FitScore ≥ 4 & savings > $100 | FitScore 3.0–3.9 or savings $25–$100 | FitScore ≥ 4 & savings < $25 |
| Deallocated VM Cleanup | — | Age > 30 days | Age 15–30 days | Age 7–15 days |
| VMSS Rightsizing | — | FitScore ≥ 4 & savings > $100 | FitScore 3.0–3.9 or savings $25–$100 | FitScore ≥ 4 & savings < $25 |
| FitScore Constraint Violation | Production resources | Non-production resources | — | — |

### Storage Optimization

| Finding Type | Critical | High | Medium | Low |
|---|---|---|---|---|
| Unattached Premium Disk (> $50/mo) | — | ✅ | — | — |
| Unattached Standard Disk (< $10/mo) | — | — | — | ✅ |
| Unattached Disk ($10–$50/mo) | — | — | ✅ | — |
| Aged Snapshot (> 90 days, > 100 GB) | — | ✅ | — | — |
| Aged Snapshot (> 90 days, < 100 GB) | — | — | ✅ | — |
| Storage Tier Mismatch | — | Savings > $100/mo | Savings $25–$100/mo | Savings < $25/mo |
| No Lifecycle Policy | — | — | — | ✅ |

### Network Optimization

| Finding Type | Critical | High | Medium | Low |
|---|---|---|---|---|
| Unused Load Balancer | — | Cost > $50/mo | ✅ (any cost) | — |
| Unused Application Gateway | — | ✅ Always (high cost) | — | — |
| Unassociated Public IP (Standard) | — | — | ✅ | — |
| Unassociated Public IP (Basic) | — | — | — | ✅ (no cost, but cleanup) |
| Default-only NSG | — | — | — | ✅ |
| Unused NAT Gateway | — | — | ✅ | — |

### PaaS Optimization

| Finding Type | Critical | High | Medium | Low |
|---|---|---|---|---|
| Empty App Service Plan (Premium+) | — | ✅ | — | — |
| Empty App Service Plan (Basic/Standard) | — | — | ✅ | — |
| App Service Rightsizing | — | Savings > $100/mo | Savings $25–$100/mo | Savings < $25/mo |
| SQL DB Rightsizing | — | Savings > $100/mo | Savings $25–$100/mo | Savings < $25/mo |
| SQL Elastic Pool Opportunity | — | — | ✅ | — |

### Governance & Compliance

| Finding Type | Critical | High | Medium | Low |
|---|---|---|---|---|
| Expired Credential | ✅ Always | — | — | — |
| Credential Expiring ≤ 7 days | — | ✅ | — | — |
| Credential Expiring 7–30 days | — | — | ✅ | — |
| Outdated API Version | — | — | — | ✅ |
| Missing Required Tags | — | — | — | ✅ |

---

## Escalation Rules

| Severity | Action | Details |
|---|---|---|
| **Critical** | Auto-create ticket + Immediate alert | Create ServiceNow incident (Urgency: 1-High, Impact: 1-High). Send Teams adaptive card. Trigger PagerDuty alert. |
| **High** | Email notification + Optional ticket | Include in email alert sent within 1 hour of scan completion. Create ServiceNow change request if auto-ticketing is enabled. |
| **Medium** | Weekly report | Include in the weekly optimization digest email. No individual notifications. |
| **Low** | Weekly report only | Include in the weekly optimization digest email. No individual notifications. |

See [Escalation-Criteria.md](Escalation-Criteria.md) for detailed escalation procedures, ticket templates, and integration configurations.

---

## Severity Override via Tags

Teams can override severity for specific resources using the `aoe:severity` tag:

| Tag Value | Effect |
|---|---|
| `aoe:severity` = `suppress` | Finding is logged but excluded from reports and escalation |
| `aoe:severity` = `low` | Override severity to Low regardless of calculated value |

**Constraints:**
- Severity can only be **lowered** via tags, never raised
- Critical findings for **expired credentials** cannot be suppressed (security requirement)
- Suppressions are logged for audit purposes

---

## Compound Severity Rules

When multiple findings exist for the same resource, the **highest severity** is used for escalation, but all findings are included in the ticket/report.

Example:
- VM has rightsizing recommendation (Medium)
- VM is also stopped-not-deallocated (Critical)
- → Escalation uses **Critical** severity
- → Ticket includes both findings
