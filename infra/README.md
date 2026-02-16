# SRE Optimization Engine — Bicep Deployment Guide

## Prerequisites

| Requirement | How to check |
|-------------|-------------|
| Azure CLI ≥ 2.60 | `az version` |
| Bicep CLI | `az bicep version` (auto-installs if missing) |
| Logged in | `az login` |
| `Microsoft.App` registered | `az provider show --namespace Microsoft.App --query registrationState` |
| Owner or User Access Admin on subscription | Required for RBAC assignment |
| SRE Agent Preview access | Request via [aka.ms/sre-agent](https://aka.ms/sre-agent) |

## Quick Start

```powershell
# From repo root:
.\scripts\deploy.ps1
```

That's it. The script validates prerequisites, deploys the Bicep template, assigns all RBAC roles, and waits for the knowledge graph to finish building.

## What Gets Deployed

The Bicep template creates these resources in a single `az deployment sub create`:

| Resource | Type | Purpose |
|----------|------|---------|
| **SRE Agent** | `Microsoft.App/agents` | The agent runtime |
| **User-Assigned MI** | `Microsoft.ManagedIdentity/userAssignedIdentities` | Identity for knowledge graph + tool execution |
| **Log Analytics** | `Microsoft.OperationalInsights/workspaces` | Agent telemetry storage |
| **Application Insights** | `Microsoft.Insights/components` | Agent monitoring + diagnostics |
| **RBAC roles** | `Microsoft.Authorization/roleAssignments` | Reader, Monitoring Reader, Log Analytics Reader, Contributor (High), App Insights Contributor, SRE Agent Administrator |

### Why User-Assigned Identity Matters

> **Root cause of `BuildingKnowledgeGraph` stuck state:**  
> The agent requires a **User-Assigned Managed Identity** referenced in three configuration blocks:
> - `knowledgeGraphConfiguration.identity` — used to build/query the knowledge graph  
> - `actionConfiguration.identity` — used to execute tools (Az CLI, etc.)  
> - `logConfiguration` — App Insights connection for telemetry  
>
> Without these, the agent provisions successfully (`provisioningState: Succeeded`)  
> but gets **permanently stuck** in `BuildingKnowledgeGraph` because it has no  
> identity to authenticate with. This matches the official Bicep template at  
> [`microsoft/sre-agent/samples/bicep-deployment`](https://github.com/microsoft/sre-agent/tree/main/samples/bicep-deployment).

## File Structure

```
infra/
├── main.bicep                          # Entry point (subscription-scoped)
├── main.parameters.json                # Default parameters (Sweden Central)
├── modules/
│   ├── sre-agent-resources.bicep       # All resources (RG-scoped)
│   └── role-assignments-target.bicep   # RBAC for target resource groups
└── examples/
    └── multi-rg.parameters.json        # Example: multi-RG targeting
```

## Parameters

### Required

| Parameter | Description | Example |
|-----------|-------------|---------|
| `agentName` | Name of the SRE Agent | `sre-optimization-agent` |
| `resourceGroupName` | Resource group (created if missing) | `rg-sre-optimization` |

### Optional

| Parameter | Default | Description |
|-----------|---------|-------------|
| `location` | `swedencentral` | Region (`swedencentral`, `eastus2`, `australiaeast`, `uksouth`) |
| `accessLevel` | `High` | `High` = Reader + Monitoring Reader + Log Analytics Reader + Contributor; `Low` = Reader + Log Analytics Reader |
| `agentMode` | `Review` | `Review` (requires approval), `Autonomous` (auto-execute), `ReadOnly` |
| `existingManagedIdentityId` | `""` | Reuse an existing UA identity instead of creating a new one |
| `targetResourceGroups` | `[]` | Additional RGs the agent should have access to |
| `targetSubscriptions` | `[]` | Subscription IDs for cross-sub target RGs |
| `tags` | `{project, phase, SecurityControl}` | Resource tags |

## Deployment Options

### Option A: PowerShell Script (Recommended)

```powershell
# Default (Sweden Central, PoC config)
.\scripts\deploy.ps1

# Custom parameters file
.\scripts\deploy.ps1 -ParametersFile .\infra\examples\multi-rg.parameters.json

# Override location, longer wait
.\scripts\deploy.ps1 -Location swedencentral -MaxWaitMinutes 45

# Deploy without waiting for knowledge graph
.\scripts\deploy.ps1 -WaitForRunning $false
```

### Option B: Azure CLI Direct

```bash
az deployment sub create \
  --name "sre-agent-$(date +%Y%m%d-%H%M%S)" \
  --location swedencentral \
  --template-file infra/main.bicep \
  --parameters @infra/main.parameters.json
```

### Option C: Override parameters inline

```bash
az deployment sub create \
  --location swedencentral \
  --template-file infra/main.bicep \
  --parameters @infra/main.parameters.json \
  --parameters location=swedencentral agentMode=Autonomous accessLevel=Low
```

## After Deployment

Once the agent reaches `runningState: Running`:

### 1. Create the Compute Optimization Subagent

Open the portal URL (printed by the deploy script) → **Subagent Builder** → **Create** → **Subagent**:

- **Name**: `Compute-Optimization-Specialist`
- **Type**: `Autonomous`
- **Instructions**: Copy the `system_prompt` field from [subagent.yaml](../subagent.yaml)
- **Handoff description**: Copy the `handoff_description` field from [subagent.yaml](../subagent.yaml)
- **Tools**: Select all tools listed in the `tools` section of [subagent.yaml](../subagent.yaml)

### 2. Upload Knowledge Base Documents

Upload all files from [`knowledge-base/`](../knowledge-base/):

| Document | Purpose |
|----------|---------|
| FitScore-Methodology.md | Core validation algorithm |
| SKU-Constraint-Rules.md | Hard/soft constraint definitions |
| Threshold-Defaults.md | Default metric thresholds |
| Metric-Collection-Guide.md | KQL queries for P99 metrics |
| Recommendation-Format.md | Output report template |
| Savings-Estimation.md | Pricing API usage |
| Severity-Classification.md | Critical/High/Medium/Low rules |
| Resource-Graph-Queries.md | ARG query patterns |
| Escalation-Criteria.md | When to escalate to humans |
| Workload-Patterns.md | Workload pattern recognition |

### 3. Create Scheduled Task (Optional)

**Schedule** → **Create Scheduled Task**:
- **Schedule**: Weekly, Monday 6:00 AM UTC
- **Subagent**: Compute-Optimization-Specialist
- **Prompt**: "Run the full compute optimization workflow for all subscriptions. Email the report to the team."

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `BuildingKnowledgeGraph` forever | Missing `knowledgeGraphConfiguration` / no UA identity | Use this Bicep template — it includes all required config |
| `Microsoft.App` not registered | Provider not registered | `az provider register --namespace Microsoft.App` |
| Deployment fails with `AuthorizationFailed` | Insufficient permissions | Need Owner or User Access Admin for RBAC assignments |
| Portal shows "access denied" | Missing SRE Agent Administrator role | Bicep auto-assigns this via `deployer().objectId` |
| Agent can't read resources | Missing RBAC on target RGs | Add RGs to `targetResourceGroups` parameter and redeploy |
| `InvalidTemplate` error | Bicep CLI outdated | `az bicep upgrade` |
| Knowledge graph takes >30 min | Normal for some regions | Wait up to 45 min; if still stuck, delete agent + all resources and redeploy |

## Clean Up

```bash
# Delete everything (agent, identity, App Insights, Log Analytics, RBAC)
az group delete --name rg-sre-optimization --yes --no-wait
```

## Known Issues

See [microsoft/sre-agent issues](https://github.com/microsoft/sre-agent/issues) for the latest. Key ones affecting this project:

| # | Issue | Impact | Workaround |
|---|-------|--------|------------|
| 51 | Internal errors corrupt thread | Agent stops responding | Start new conversation thread |
| 53 | Az CLI hangs silently | Workflow stalls | Instructions include 60s timeout guidance |
| 55 | RBAC inconsistency | User B blocked despite roles | Bicep handles all RBAC automatically |
| 60 | Tools not always available | Tool calls fail | Instructions include retry logic |
| 67 | Scheduled email not delivered | Reports lost | Fallback to UploadKnowledgeDocument |
