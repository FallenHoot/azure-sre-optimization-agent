# Azure SRE Agent — Reference Instructions & Best Practices

> **Purpose**: Central reference for building, deploying, and maintaining SRE Agent subagents.
> Keep this file up-to-date with the latest MS Learn docs, GitHub samples, and discovered platform constraints.

---

## 1. Official MS Learn Documentation

### Core Documentation

| Topic | URL | Notes |
|---|---|---|
| **SRE Agent Overview** | https://learn.microsoft.com/en-us/azure/sre-agent/overview | Service description, capabilities, integrations, how it works |
| **Use an Agent** | https://learn.microsoft.com/en-us/azure/sre-agent/usage | First incident walkthrough, getting started |
| **Subagent Builder Overview** | https://learn.microsoft.com/en-us/azure/sre-agent/subagent-builder-overview | Create subagents — name, instructions, handoff, tools, knowledge base |
| **Subagent Builder Scenarios** | https://learn.microsoft.com/en-us/azure/sre-agent/subagent-builder-scenarios | YAML examples, data connectors, triggers, scheduled tasks, subagent types |
| **Billing** | https://learn.microsoft.com/en-us/azure/sre-agent/billing | AAU pricing — always-on (4 AAU/hr) + active flow (0.25 AAU/sec) |
| **FAQ — General** | https://learn.microsoft.com/en-us/azure/sre-agent/faq | Regions, permissions, capabilities, data privacy |
| **FAQ — Troubleshooting** | https://learn.microsoft.com/en-us/azure/sre-agent/faq-troubleshooting | Operations troubleshooting |
| **FAQ — Security & Compliance** | https://learn.microsoft.com/en-us/azure/sre-agent/faq-security-compliance | Security and compliance FAQ |
| **Data Residency & Privacy** | https://learn.microsoft.com/en-us/azure/sre-agent/data-privacy | Where data is stored, privacy policies |
| **Custom MCP Server** | https://learn.microsoft.com/en-us/azure/sre-agent/custom-mcp-server | Connect external MCP servers — SSE/HTTP, authentication |
| **Connectors** | https://learn.microsoft.com/en-us/azure/sre-agent/connectors | Azure Monitor, PagerDuty, ServiceNow, Teams, Outlook, GitHub, ADO |

### Key Takeaways from MS Learn

- **English only** — chat interface only supports English.
- **Regional availability** — Sweden Central, East US 2, Australia East (UK South for Bicep deployments).
- **Agent auto-creates**: Application Insights, Log Analytics workspace, Managed Identity.
- **Data never used for training** — enterprise-grade AI, strict data handling.
- **MCP tools only accessible through subagents**, not the main agent directly.
- **Knowledge base** supports `.md` and `.txt` files, max 50 MB per file, up to 1,000 files per agent.

---

## 2. GitHub Samples Repository

### Repository

| Resource | URL |
|---|---|
| **Samples Root** | https://github.com/microsoft/sre-agent/tree/main/samples |
| **Bicep Deployment Guide** | https://github.com/microsoft/sre-agent/blob/main/samples/bicep-deployment/deployment-guide.md |
| **Bicep Templates** | https://github.com/microsoft/sre-agent/tree/main/samples/bicep-deployment/bicep |
| **Deploy Script** | https://github.com/microsoft/sre-agent/blob/main/samples/bicep-deployment/scripts/deploy.sh |
| **Incident Automation** | https://github.com/microsoft/sre-agent/tree/main/samples/automation |
| **Proactive Reliability Demo** | https://github.com/microsoft/sre-agent/tree/main/samples/proactive-reliability |
| **Issues & Bug Reports** | https://github.com/microsoft/sre-agent/issues |

### Samples Folder Structure

```
samples/
├── bicep-deployment/              # IaC templates for deploying SRE Agents
│   ├── bicep/
│   │   ├── minimal-sre-agent.bicep         # Main template (subscription-scoped)
│   │   ├── sre-agent-resources.bicep       # Resource group-scoped module
│   │   ├── role-assignments-minimal.bicep  # Deployment RG role assignments
│   │   └── role-assignments-target.bicep   # Target RG role assignments
│   ├── examples/
│   └── scripts/
│       ├── deploy.sh                       # Interactive deployment script
│       └── quick-deploy-no-targets.sh      # Quick standalone deployment
├── automation/                    # Incident automation samples
│   ├── configuration/
│   │   └── 00-configure-sre-agent.md       # Step-by-step agent configuration
│   ├── samples/
│   │   ├── 01-incident-automation-sample.md  # PagerDuty + Octopets memory leak
│   │   └── 02-scheduled-health-check-sample.md # Daily health check
│   ├── sample-apps/
│   │   └── octopets-setup.md               # Deploy sample Octopets app
│   ├── subagents/
│   │   ├── pd-azure-resource-error-handler.yaml  # PagerDuty error handler YAML
│   │   └── health-check-agent.yaml               # Health check agent YAML
│   └── images/
└── proactive-reliability/         # Proactive remediation demo
    ├── SubAgents/
    │   ├── AvgResponseBaseline.yaml        # Baseline capture agent YAML
    │   ├── DeploymentHealthCheck.yaml      # Health check + remediation YAML
    │   └── DeploymentReporter.yaml         # Report generation YAML
    ├── infrastructure/
    │   └── main.bicep                      # Demo infra (App Service, AppInsights, Alerts)
    └── scripts/
        ├── 1-setup-demo.ps1                # One-time infrastructure setup
        └── 2-run-demo.ps1                  # Run the live demo
```

### Key Patterns from GitHub Samples

1. **Subagent YAML config via portal**: Edit subagent → YAML tab → paste YAML → Save
2. **Three-agent pattern** (from proactive-reliability):
   - Baseline agent (scheduled) → captures metrics, stores in Knowledge Store
   - Health check agent (incident-triggered) → compares to baseline, remediates
   - Reporter agent (scheduled) → summarizes activity, sends notifications
3. **Tool categories used in samples**:
   - Knowledge Base: `SearchMemory`, `UploadKnowledgeDocument`
   - App Insights: `QueryAppInsightsByAppId`
   - Communication: `PostTeamsMessage`, `SendOutlookEmail`, `GetTeamsMessages`
   - DevOps: `CreateGithubIssue`, `QuerySourceBySemanticSearch`, `FindConnectedGitHubRepo`
   - Azure CLI: `GetAzCliHelp`, `RunAzCliReadCommands`, `RunAzCliWriteCommands`

---

## 3. Platform Constraints & Limits

### ⚠️ Hard Limits (Validated)

| Constraint | Limit | Impact |
|---|---|---|
| **Instructions (system_prompt)** | **≤ 20,000 characters** | Deployment will fail if exceeded |
| **Handoff description** | **≤ 500 characters** | Deployment will fail if exceeded |
| **Knowledge base files** | ≤ 1,000 files per agent | Soft limit |
| **File size** | ≤ 50 MB per file | Upload will fail |
| **Supported file types** | `.md`, `.txt` only | For knowledge base uploads |

### Character Budget Strategy

When instructions exceed 20,000 characters:
1. **Externalize** CLI command templates, ARG queries, step-by-step procedures → move to KB docs (`.md` files)
2. **Keep in system_prompt** only behavioral rules, hard constraints, output format, error handling, tool-NOT-available lists
3. **Reference KB docs** via `SearchMemory` tool — the agent can retrieve externalized content at runtime
4. **Measure** using: `(Get-Content -Raw subagent.yaml | Select-String -Pattern 'instructions: \|' -Context 0,9999).Context.PostContext | Measure-Object -Character`

### Current Character Usage (Our Subagents)

| Subagent | Instructions | Headroom | Handoff | Headroom |
|---|---|---|---|---|
| compute-optimization | 12,289 ✅ | 7,711 | 465 ✅ | 35 |
| storage-optimization | 9,034 ✅ | 10,966 | 493 ✅ | 7 |
| network-optimization | 17,387 ✅ | 2,613 | 475 ✅ | 25 |
| paas-optimization | 19,098 ✅ | 902 | 436 ✅ | 64 |
| orchestrator | 15,186 ✅ | 4,814 | 346 ✅ | 154 |
| governance-compliance | 15,983 ✅ | 4,017 | 351 ✅ | 149 |

---

## 4. Subagent YAML Structure

### Official YAML Schema (from MS Learn Scenarios doc)

```yaml
agent:
  name: "SubagentName"
  description: "What this subagent does"
  instructions: |
    You are a specialist in [domain].
    Focus on [specific areas] when investigating incidents.
  tools:
    - "ToolName1"
    - "ToolName2"
  handoff_conditions:
    - "Scenario when other agents should transfer to this agent"
```

### Subagent Configuration Fields

| Field | Required | Max Length | Description |
|---|---|---|---|
| `name` | ✅ | — | Descriptive name for the subagent |
| `instructions` | ✅ | **20,000 chars** | System prompt — behavioral rules, constraints, procedures |
| `handoff_description` | ✅ | **500 chars** | When other subagents should hand off to this one |
| `tools` (built-in) | Optional | — | Select from available system tools |
| `tools` (custom/MCP) | Optional | — | Custom tools from connected MCP servers |
| `handoff_agents` | Optional | — | Which subagents to hand off to after completion |
| `knowledge_base` | Optional | — | Enable/disable KB access for this subagent |

### Portal Workflow

1. Go to your SRE Agent in Azure Portal
2. Select **Subagent builder** tab
3. Click **Create** → **Subagent**
4. Fill in: Name, Instructions, Handoff Description
5. Select Built-in Tools and/or Custom Tools
6. Optionally configure Handoff Agents and Knowledge Base
7. Click **Create subagent**
8. For YAML editing: Edit subagent → select **YAML** tab → paste/modify → **Save**

---

## 5. Trigger Configuration

### Incident Triggers

Connect subagents to fire automatically when Azure Monitor alerts match conditions:
- **Platform**: Azure Monitor, PagerDuty, ServiceNow
- **Filters**: Severity level, title contains, service impact
- **Response mode**: Review (human approval) or Autonomous

```yaml
trigger:
  name: "High-CPU-Alert-Response"
  platform: "AzureMonitor"
  conditions:
    - metric: "cpu_percent"
    - threshold: "> 90%"
    - duration: "5 minutes"
  response:
    agent: "WebApp-Performance-Specialist"
    mode: "review"
    timeout: "30 minutes"
```

### Scheduled Tasks

Recurring automation on cron schedules:
- Cron expressions (e.g., `0 9 * * 1-5` for weekdays at 9 AM)
- Preset intervals: hourly, daily, weekly, monthly

```yaml
scheduled_task:
  name: "Daily-Health-Report"
  schedule: "0 9 * * 1-5"
  timezone: "UTC"
  instructions: |
    Generate a comprehensive health report covering:
    - Resource utilization trends
    - Active alerts and resolution status
    - Recent deployment impacts
    - Optimization recommendations
  outputs:
    - email: "ops-team@company.com"
    - teams_channel: "operations-reports"
```

---

## 6. Bicep Deployment Reference

### API Version

```
Microsoft.App/agents@2025-05-01-preview
```

### Required Bicep Parameters

| Parameter | Description |
|---|---|
| `agentName` | Name of the SRE Agent |
| `deploymentResourceGroupName` | RG where agent resources live |

### Optional Parameters

| Parameter | Default | Description |
|---|---|---|
| `subscriptionId` | Current subscription | Target subscription |
| `location` | `eastus2` | Allowed: `swedencentral`, `uksouth`, `eastus2`, `australiaeast` |
| `existingManagedIdentityId` | (create new) | Use existing managed identity |
| `accessLevel` | `High` | `High` (Reader + Contributor + Log Analytics) or `Low` (Reader + Log Analytics) |
| `targetResourceGroups` | `[]` | RGs the agent can manage |
| `targetSubscriptions` | `[]` | Subscriptions for cross-sub targeting |

### Quick Deploy Command

```bash
az deployment sub create \
  --subscription "<SUBSCRIPTION_ID>" \
  --location "swedencentral" \
  --template-file minimal-sre-agent.bicep \
  --parameters \
    agentName="my-sre-agent" \
    subscriptionId="<SUBSCRIPTION_ID>" \
    deploymentResourceGroupName="rg-sre-agent" \
    location="swedencentral" \
    accessLevel="High" \
    targetResourceGroups='["rg-target-workloads"]'
```

### Cross-Subscription Targeting

Arrays are matched by index — first resource group uses first subscription:

```json
{
  "targetResourceGroups": { "value": ["rg-prod-web", "rg-prod-data"] },
  "targetSubscriptions": { "value": ["sub-id-1", "sub-id-1"] }
}
```

### Role Assignments Created

| Access Level | Roles Assigned |
|---|---|
| **Low** | Log Analytics Reader, Reader |
| **High** | Log Analytics Reader, Reader, Contributor |

Additionally, the deploying user gets **SRE Agent Administrator** (`e79298df-d852-4c6d-84f9-5d13249d1e55`).

---

## 7. Built-in Tools Reference

### Azure-Specific Tools

| Tool | Category | Description |
|---|---|---|
| `RunAzCliReadCommands` | Azure CLI | Execute read-only Azure CLI commands |
| `RunAzCliWriteCommands` | Azure CLI | Execute write Azure CLI commands (privileged mode) |
| `GetAzCliHelp` | Azure CLI | Get Azure CLI command help |
| `QueryAppInsightsByAppId` | Monitoring | Query Application Insights |
| `SearchMemory` | Knowledge Base | Search uploaded KB documents |
| `UploadKnowledgeDocument` | Knowledge Base | Store documents in agent's knowledge store |

### Communication Tools

| Tool | Category | Description |
|---|---|---|
| `PostTeamsMessage` | Communication | Post to Microsoft Teams channels |
| `GetTeamsMessages` | Communication | Read Teams channel messages |
| `SendOutlookEmail` | Communication | Send email via Outlook |

### DevOps Tools

| Tool | Category | Description |
|---|---|---|
| `CreateGithubIssue` | GitHub | Create GitHub issues |
| `FindConnectedGitHubRepo` | GitHub | Discover connected repositories |
| `QuerySourceBySemanticSearch` | GitHub | Semantic code search in repos |

---

## 8. Best Practices (Learned from Microsoft Samples)

### Instruction Writing

1. **Be specific** — define the subagent's exact domain, scope, and operational focus
2. **Define output format** — specify exactly what the response should look like
3. **List constraints** — what the agent must NOT do (e.g., "never recommend retiring SKUs")
4. **Include error handling** — what to do when tools fail or data is unavailable
5. **Reference KB docs** — use `SearchMemory` to retrieve detailed procedures at runtime instead of embedding them in instructions

### Handoff Descriptions

1. **Keep under 500 characters** — hard limit
2. **Focus on WHEN to transfer** — describe the triggering condition, not the subagent's capabilities
3. **Be mutually exclusive** — avoid overlap between subagent handoff descriptions
4. **Use action-oriented language** — "Transfer when the user asks about compute VM sizing..."

### Knowledge Base Strategy

1. **Externalize bulky content** — CLI command templates, ARG queries, step-by-step procedures
2. **Keep behavioral rules in instructions** — the system_prompt should contain decision logic, not reference data
3. **Use consistent naming** — prefix KB files with their domain (e.g., `FitScore-Methodology.md`, `Resource-Graph-Queries.md`)
4. **Supported formats**: Markdown (`.md`) and text (`.txt`) only

### Multi-Subagent Architecture

1. **Orchestrator pattern** — one orchestrator routes to domain specialists
2. **Avoid circular handoffs** — define clear handoff chains
3. **Test in Playground first** — use the portal Playground to validate before connecting triggers
4. **Start in Review mode** — test with human approval before switching to Autonomous

### Pricing Awareness

- **Always-on**: 4 AAU/hr = ~$292/mo baseline per agent
- **Active flow**: 0.25 AAU/sec per task — cost accumulates while agent processes
- **Monthly cap**: Configure `monthlyAgentUnitLimit` to control spend (e.g., 10,000 AAU = ~$1,000/mo max)
- **Billing starts**: September 1, 2025

---

## 9. Our Agent Configuration

### Agent Details

| Property | Value |
|---|---|
| Resource Type | `Microsoft.App/agents` |
| Name | `sre-optimization-agent` |
| RG | `rg-sre-optimization` |
| Region | `swedencentral` |
| Agent Subscription | `0a659fdc-7842-48ca-a297-09d166711ef7` |
| Demo Subscription | `529744b7-01d5-4f39-9d5b-3ccdea48ab04` |
| Managed Identity | `5d22404e-6d12-4d97-8bb2-994583623d3a` |
| AAU Cap | 10,000/month |
| RBAC | Reader + Monitoring Reader + Log Analytics Reader on both subscriptions |

### Subagent Architecture

```
orchestrator (routes all user requests)
  ├── compute-optimization (VMs, VMSS, disks, Spot, FitScore)
  ├── storage-optimization (storage accounts, blobs, tiers, lifecycle)
  ├── network-optimization (NSGs, load balancers, VPN, ExpressRoute)
  ├── paas-optimization (App Service, AKS, SQL, Cosmos DB, Functions)
  └── governance-compliance (policies, RBAC, tagging, cost governance)
```

### Source of Truth Hierarchy

1. **Live Azure APIs** — Azure Resource Graph, Azure Monitor, Pricing API
2. **MS Learn Documentation** — referenced via URLs for the latest guidance
3. **Static KB Files** — 10 files in `knowledge-base/` directory for procedures and reference data

---

## 10. Troubleshooting

### Common Issues

| Problem | Solution |
|---|---|
| Deployment fails with character limit | Measure instructions char count; externalize content to KB docs |
| Agent not responding to prompts | Check agent state: `az resource show --resource-type 'Microsoft.App/agents'` |
| Tools not available in subagent | Verify tools are selected in Subagent Builder; MCP tools need connector setup first |
| Cross-subscription access denied | Verify RBAC role assignments on target subscription for managed identity |
| Knowledge base not searchable | Ensure files are `.md` or `.txt`; check file was uploaded and indexed |

### Issue Reporting Template (from GitHub)

When filing issues at https://github.com/microsoft/sre-agent/issues:
- **Agent Name**: name of Agent
- **Subscription ID**: subscription where agent is deployed
- **Region**: deployment region
- **Resource Group**: RG where agent lives
- **Thread ID**: from the SRE Agent portal
- **Steps to Reproduce**: action taken, resource involved, expected vs actual
- **Error messages**: from incident/chat threads, ARM deployment errors, HTTP status codes

---

## 11. Changelog

| Date | Change |
|---|---|
| 2025-07-15 | Initial creation — compiled from MS Learn, GitHub samples, and project learnings |
