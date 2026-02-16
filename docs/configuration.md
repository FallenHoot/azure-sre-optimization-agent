# Configuration Guide

This guide explains how to customize the SRE Agent Optimization Engine Subagents for your environment, including threshold overrides, schedule changes, notification setup, and multi-subscription configuration.

---

## 1. Threshold Overrides

Default thresholds are defined in [knowledge-base/Threshold-Defaults.md](../knowledge-base/Threshold-Defaults.md). You can override them at three levels:

### Override Hierarchy (Highest Priority First)

1. **Resource-level** (via Azure tags) — highest priority
2. **Resource-group-level** (via Azure tags)
3. **Subscription-level** (via configuration)
4. **Global defaults** (knowledge base) — lowest priority

### 1.1 Resource-Level Overrides (Tags)

Apply Azure tags to individual resources to override thresholds:

```bash
# Override CPU threshold for a specific VM (set to 90% instead of default 80%)
az vm update \
  --resource-group myRG \
  --name myVM \
  --set tags.opt-cpu-threshold=90

# Override memory threshold
az vm update \
  --resource-group myRG \
  --name myVM \
  --set tags.opt-memory-threshold=90

# Exclude a resource from optimization scanning
az vm update \
  --resource-group myRG \
  --name myVM \
  --set tags.opt-exclude=true
```

#### Supported Override Tags

| Tag | Default | Description |
|---|---|---|
| `opt-cpu-threshold` | 80 | CPU utilization threshold (%) for soft constraint |
| `opt-memory-threshold` | 80 | Memory utilization threshold (%) for soft constraint |
| `opt-iops-threshold` | 80 | IOPS utilization threshold (%) for soft constraint |
| `opt-network-threshold` | 80 | Network utilization threshold (%) for soft constraint |
| `opt-deallocated-days` | 30 | Days deallocated before flagging for deletion |
| `opt-exclude` | false | Exclude resource from all optimization scans |
| `opt-severity-override` | — | Override auto-calculated severity (Critical/High/Medium/Low) |
| `opt-owner` | — | Resource owner email for notifications |

### 1.2 Resource-Group-Level Overrides (Tags)

Apply tags to the resource group to override thresholds for all resources within it:

```bash
# Override CPU threshold for all resources in a resource group
az group update \
  --name myRG \
  --tags opt-cpu-threshold=90

# Exclude entire resource group from scanning
az group update \
  --name myRG \
  --tags opt-exclude=true
```

> **Note:** Resource-level tags take precedence over resource-group-level tags.

### 1.3 Subscription-Level Overrides

For subscription-wide overrides, modify the subagent YAML configuration:

```yaml
# subagents/compute-optimization/subagent.yaml
configuration:
  thresholds:
    cpu_threshold: 85          # Override default 80%
    memory_threshold: 85       # Override default 80%
    deallocated_days: 14       # Flag after 14 days instead of 30
    metric_window_days: 14     # Use 14-day P99 instead of 7-day
```

---

## 2. Schedule Changes

### Modifying Schedules

Edit the `schedule.yaml` file for each subagent:

```yaml
# subagents/compute-optimization/schedule.yaml
schedule:
  # Cron expression: minute hour day-of-month month day-of-week
  cron: "0 6 * * *"           # Daily at 06:00 UTC
  timezone: "UTC"
  enabled: true
```

### Common Schedule Patterns

| Pattern | Cron Expression | Description |
|---|---|---|
| Daily at 6 AM UTC | `0 6 * * *` | Standard daily check |
| Weekdays at 8 AM UTC | `0 8 * * 1-5` | Business days only |
| Weekly Monday 9 AM UTC | `0 9 * * 1` | Weekly governance checks |
| Every 6 hours | `0 */6 * * *` | High-frequency monitoring |
| First day of month | `0 6 1 * *` | Monthly reports |

### Disabling a Schedule

```yaml
# subagents/network-optimization/schedule.yaml
schedule:
  cron: "0 8 * * 1"
  enabled: false              # Disabled — will not run automatically
```

---

## 3. Email Notifications

### Configure Email Recipients

```yaml
# subagents/orchestrator/subagent.yaml
notifications:
  email:
    enabled: true
    recipients:
      - sre-team@company.com
      - cloud-finops@company.com
    severity_filter:
      - Critical
      - High                  # Only send emails for Critical and High severity
    format: summary           # "summary" or "detailed"
```

### Notification Triggers

| Trigger | Description |
|---|---|
| `on_completion` | Send after each scheduled run |
| `on_critical` | Send immediately for Critical severity findings |
| `on_high_savings` | Send when total potential savings exceed threshold |
| `on_error` | Send when subagent encounters an error |

```yaml
notifications:
  email:
    triggers:
      - on_completion
      - on_critical
    high_savings_threshold: 1000   # Notify if savings > $1,000/month
```

---

## 4. Ticket Integration

### ServiceNow Integration

```yaml
# subagents/orchestrator/subagent.yaml
integrations:
  servicenow:
    enabled: true
    instance_url: "https://company.service-now.com"
    auth_method: managed_identity   # or api_key
    auto_create_tickets: true
    severity_filter:
      - Critical
      - High
    assignment_group: "Cloud SRE Team"
    category: "Cost Optimization"
```

### Azure DevOps Integration

```yaml
integrations:
  azure_devops:
    enabled: true
    organization: "https://dev.azure.com/company"
    project: "Cloud Operations"
    work_item_type: "Task"
    auto_create: true
    severity_filter:
      - Critical
      - High
    area_path: "Cloud Operations\\Cost Optimization"
```

---

## 5. Adding Custom Knowledge Base Documents

### Creating a Custom Document

1. Create a new markdown file in the `knowledge-base/` directory:

```markdown
# Custom Threshold Rules for Production

## Context
Production workloads in the "prod-*" resource groups require higher thresholds.

## Rules
- CPU threshold: 90% (instead of 80%)
- Memory threshold: 90% (instead of 80%)
- Minimum FitScore for recommendations: 4.5 (instead of 4.0)
- Deallocated VM threshold: 7 days (instead of 30)

## Scope
Apply to resource groups matching: prod-*
```

2. Upload the document:

```bash
# az sre-agent knowledge-base upload \
#   --resource-group $AGENT_RG \
#   --agent-name $AGENT_NAME \
#   --file "knowledge-base/Custom-Prod-Rules.md"
```

### Knowledge Base Document Guidelines

- Use clear, declarative language (the LLM interprets these as instructions)
- Include specific threshold values and scope definitions
- Reference other knowledge base documents by name when needed
- Keep documents focused on a single topic

---

## 6. Multi-Subscription Setup

### Adding Additional Subscriptions

1. **Configure RBAC** for each subscription:

```bash
# For each additional subscription
./scripts/setup-rbac.sh \
  --identity-id $IDENTITY_ID \
  --subscription-id <additional-subscription-id>
```

2. **Update the orchestrator scope**:

```yaml
# subagents/orchestrator/subagent.yaml
scope:
  subscriptions:
    - id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
      name: "Production"
      enabled: true
    - id: "ffffffff-gggg-hhhh-iiii-jjjjjjjjjjjj"
      name: "Development"
      enabled: true
    - id: "kkkkkkkk-llll-mmmm-nnnn-oooooooooooo"
      name: "Staging"
      enabled: true
```

3. **Per-subscription schedule overrides** (optional):

```yaml
scope:
  subscriptions:
    - id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
      name: "Production"
      schedule_override:
        cron: "0 6 * * *"          # Daily for production
    - id: "ffffffff-gggg-hhhh-iiii-jjjjjjjjjjjj"
      name: "Development"
      schedule_override:
        cron: "0 9 * * 1"          # Weekly for dev
```

### Multi-Subscription Output

When scanning multiple subscriptions, the orchestrator aggregates results:

```markdown
# Optimization Report — 2026-02-13

## Summary
| Subscription | Resources Scanned | Findings | Est. Savings |
|---|---|---|---|
| Production | 245 | 12 | $3,400/mo |
| Development | 89 | 34 | $1,200/mo |
| Staging | 42 | 8 | $600/mo |
| **Total** | **376** | **54** | **$5,200/mo** |
```

---

## 7. Resource Exclusions

### Exclude by Tag

```bash
# Exclude a single resource
az resource tag --ids <resource-id> --tags opt-exclude=true

# Exclude an entire resource group
az group update --name myRG --tags opt-exclude=true
```

### Exclude by Resource Type

```yaml
# subagents/compute-optimization/subagent.yaml
configuration:
  exclusions:
    resource_types:
      - "Microsoft.Compute/virtualMachineScaleSets"  # Exclude VMSS
    name_patterns:
      - "temp-*"          # Exclude resources starting with "temp-"
      - "*-donotoptimize"  # Exclude resources ending with "-donotoptimize"
    resource_groups:
      - "rg-ephemeral"    # Exclude entire resource group
```

---

## 8. Configuration Validation

After making configuration changes, validate before deploying:

```bash
# Validate all YAML configurations
for subagent in subagents/*/subagent.yaml; do
  echo "Validating $subagent..."
  # az sre-agent config validate --file "$subagent"
done

# Validate RBAC access for all configured subscriptions
./scripts/validate-access.sh --all-subscriptions
```

---

## Configuration Reference

### Full subagent.yaml Schema

```yaml
name: "compute-optimization"
description: "Compute resource optimization specialist"
version: "1.0.0"

scope:
  subscriptions:
    - id: "<subscription-id>"
      name: "<display-name>"
      enabled: true

configuration:
  thresholds:
    cpu_threshold: 80
    memory_threshold: 80
    iops_threshold: 80
    network_threshold: 80
    deallocated_days: 30
    metric_window_days: 7
    min_fitscore: 4.0

  exclusions:
    resource_types: []
    name_patterns: []
    resource_groups: []

notifications:
  email:
    enabled: false
    recipients: []
    severity_filter: [Critical, High]
    triggers: [on_completion]

integrations:
  servicenow:
    enabled: false
  azure_devops:
    enabled: false

schedule:
  cron: "0 6 * * *"
  timezone: "UTC"
  enabled: true
```
