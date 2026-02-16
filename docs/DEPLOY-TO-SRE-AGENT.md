# Deploy to Azure SRE Agent — Step-by-Step Portal Guide

This guide walks you through deploying the Compute Optimization Specialist
subagent (Phase 1 PoC) to a live Azure SRE Agent instance using the Azure Portal.

> **Prerequisites**
> - Azure subscription with SRE Agent Preview access
> - Owner or Contributor role on target resource group
> - Azure CLI installed (`az login` completed)

---

## Step 1 — Create the SRE Agent Resource

### Option A — Azure CLI (REST API, recommended)

```bash
# Register the provider (one-time)
az provider register --namespace "Microsoft.App" --wait

# Create resource group
az group create --name rg-sre-optimization --location swedencentral

# Create the agent via ARM REST API
cat > /tmp/sre-agent-body.json <<'EOF'
{
  "location": "swedencentral",
  "identity": { "type": "SystemAssigned" },
  "tags": {
    "phase": "poc",
    "project": "sre-optimization-engine",
    "SecurityControl": "Ignore"
  },
  "properties": {
    "monthlyAgentUnitLimit": 10000,
    "upgradeChannel": "Stable",
    "incidentManagementConfiguration": { "type": "AzMonitor" }
  }
}
EOF

az rest --method PUT \
  --url "https://management.azure.com/subscriptions/<subscription-id>/resourceGroups/rg-sre-optimization/providers/Microsoft.App/agents/sre-optimization-agent?api-version=2025-05-01-preview" \
  --headers "Content-Type=application/json" \
  --body @/tmp/sre-agent-body.json
```

> **Important tags:**
> - `SecurityControl: Ignore` — required in environments with Azure Policy that may block agent initialization
> - The resource type is `Microsoft.App/agents`, API version `2025-05-01-preview`
> - Available regions: `swedencentral`, `eastus2`, `australiaeast`

### Option B — Azure Portal

1. Go to the [Azure Portal](https://portal.azure.com) or [SRE Agent Portal](https://aka.ms/sreagent/portal)
2. Search for **"SRE Agent"** in the marketplace
3. Click **Create**
4. Fill in:

   | Field          | Value                              |
   |----------------|------------------------------------|
   | Subscription   | Your target subscription           |
   | Resource Group | `rg-sre-optimization` (create new) |
   | Name           | `sre-optimization-agent`           |
   | Region         | `Sweden Central` or `East US 2` or `Australia East` |

5. Click **Review + Create** → **Create**

### Post-creation: Wait for readiness

After creation, the agent enters `BuildingKnowledgeGraph` state (10–30 min):

```bash
# Check state (must reach "Running" before portal works)
az rest --method GET \
  --url "https://management.azure.com/subscriptions/<sub-id>/resourceGroups/rg-sre-optimization/providers/Microsoft.App/agents/sre-optimization-agent?api-version=2025-05-01-preview" \
  --query "properties.runningState" -o tsv
```

If stuck in `BuildingKnowledgeGraph` for 30+ minutes, delete and recreate the agent.

---

## Step 2 — Assign RBAC to the Managed Identity

After the SRE Agent is created, find its **Managed Identity** Object ID:

```bash
# Get the Managed Identity principal ID
az rest --method GET \
  --url "https://management.azure.com/subscriptions/<subscription-id>/resourceGroups/rg-sre-optimization/providers/Microsoft.App/agents/sre-optimization-agent?api-version=2025-05-01-preview" \
  --query "identity.principalId" -o tsv
```

> **Note:** The resource type is `Microsoft.App/agents` (not `Microsoft.SREAgent/sreAgents`).

Then assign the required roles (use `scripts/setup-rbac.sh` or manually):

```bash
PRINCIPAL_ID="<managed-identity-object-id>"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Reader — access Resource Graph and resource metadata
az role assignment create --assignee $PRINCIPAL_ID \
  --role "Reader" --scope "/subscriptions/$SUBSCRIPTION_ID"

# Monitoring Reader — access Azure Monitor metrics/logs
az role assignment create --assignee $PRINCIPAL_ID \
  --role "Monitoring Reader" --scope "/subscriptions/$SUBSCRIPTION_ID"

# Log Analytics Reader — run KQL queries for P99 metrics
az role assignment create --assignee $PRINCIPAL_ID \
  --role "Log Analytics Reader" --scope "/subscriptions/$SUBSCRIPTION_ID"
```

### Verify access with `scripts/validate-access.sh`:

```bash
# Test Resource Graph
az graph query -q "Resources | summarize count()" --first 1

# Test Advisor
az advisor recommendation list --category Cost --output json | head -5

# Test SKU list
az vm list-skus --location swedencentral --size Standard_D4s_v5 --output table

# Test Retail Prices (no auth needed)
curl -s "https://prices.azure.com/api/retail/prices?\$filter=armSkuName eq 'Standard_D4s_v5' and armRegionName eq 'swedencentral' and priceType eq 'Consumption'" | python -m json.tool | head -20
```

---

## Step 3 — Upload Knowledge Base Files

1. In the Azure Portal, navigate to your SRE Agent
2. Go to **Subagent builder** → **Settings** → **Knowledge Base** → **Files**
3. Upload all 10 files from the `knowledge-base/` directory:

   | File | Purpose |
   |------|---------|
   | `FitScore-Methodology.md` | **Core algorithm** — FitScore 0-5 scoring procedure |
   | `SKU-Constraint-Rules.md` | Hard vs soft constraint definitions, SKU capability lookup |
   | `Threshold-Defaults.md` | Default threshold values (CPU 30%, Memory 50%, etc.) |
   | `Recommendation-Format.md` | JSON schema for recommendation output |
   | `Savings-Estimation.md` | Retail Prices API usage, monthly/annual calculation |
   | `Severity-Classification.md` | Critical/High/Medium/Low classification rules |
   | `Resource-Graph-Queries.md` | KQL queries for VM/VMSS/disk/network discovery |
   | `Metric-Collection-Guide.md` | Azure Monitor P99 metric collection procedures |
   | `Escalation-Criteria.md` | When to escalate to human operators |
   | `Workload-Patterns.md` | Common workload patterns and scheduling considerations |

4. After upload, verify files show as **Indexed** status

> Files are Markdown (`.md`) — a supported format. Max 50 MB per file, 1,000 files per instance.

---

## Step 4 — Create the Compute Optimization Specialist Subagent

1. In your SRE Agent, select the **Subagent builder** tab
2. Click **Create** → **Subagent**
3. Fill in each field using the content from `subagents/compute-optimization/subagent.yaml`:

### Field Mapping

| Portal Field | Source in subagent.yaml | What to enter |
|---|---|---|
| **Name** | `agent.name` | `Compute-Optimization-Specialist` |
| **Instructions** | `agent.instructions` | Copy the FULL instructions block from subagent.yaml (Steps 1-9, detailed workflow) |
| **Handoff Description** | `agent.handoff_description` | `Delegate to this agent when the task involves VM or VMSS optimization, rightsizing, compute utilization analysis, FitScore validation, deallocated/idle VM detection, or high availability configuration review.` |
| **Built-in Tools** | `agent.tools` | Select: `RunAzCliReadCommands`, `RunAzCliWriteCommands`, `GetAzCliHelp`, `ExecutePythonCode`, `UploadKnowledgeDocument`, `GetActivityLogsSummary`, `GetArmResourceAsJson`, `CheckIfResourceExists`, `GetDimensionNames`, `GetCurrentUtcTime`, `SearchMemory` |
| **Knowledge Base** | Enable toggle | Toggle ON, ensure all 10 uploaded files are accessible to this subagent |

### Built-in Tools Explained

| Tool | Used In | Purpose |
|------|---------|--------|
| `RunAzCliReadCommands` | Steps 1, 3, 4, 5, 6, 7 | Execute `az graph query`, `az advisor`, `az vm list-skus`, `az monitor log-analytics query` (KQL P99 metrics), `az monitor metrics list` (fallback), `az rest` (pricing API) |
| `RunAzCliWriteCommands` | Future | Auto-remediation (Phase 3+) |
| `GetAzCliHelp` | Any | Command syntax reference |
| `ExecutePythonCode` | Step 4 | Complex FitScore calculations and data processing |
| `UploadKnowledgeDocument` | Step 8 | Save report to KB for persistence and trend analysis |
| `GetActivityLogsSummary` | Step 5 | Query activity logs for deallocated VM detection |
| `GetArmResourceAsJson` | Step 2 | Get raw VM properties, disk details |
| `CheckIfResourceExists` | Steps 1-6 | Pre-query validation |
| `GetDimensionNames` | Step 4 | Metric dimension metadata |
| `GetCurrentUtcTime` | Step 8 | Report timestamp |
| `SearchMemory` | Any | Cross-session context |

> **Note:** `AzureMonitorQuery`, `SendOutlookEmail`, `PlotTimeSeriesData`, `SearchWeb`,
> and `RunPythonCode` do **not** exist on the SRE Agent platform. See the tool mapping
> rationale in the subagent prompt for correct alternatives.
---

## Step 5 — Test in the Playground

Before scheduling, test the subagent interactively:

1. In Subagent builder, click **Playground** (test mode)
2. Try these prompts:

### Prompt 1 — Full Scan
```
Perform a complete compute optimization scan across all accessible subscriptions.
Include VM rightsizing with FitScore validation, idle resource detection, and 
high availability checks. Generate a full report with savings estimates.
```

### Prompt 2 — Single VM Analysis
```
Analyze VM "vm-web-prod-01" in resource group "rg-webapp-prod" for rightsizing 
opportunities. Calculate the FitScore for the Advisor-recommended target SKU 
and provide a detailed breakdown.
```

### Prompt 3 — Idle Detection Only
```
Find all VMs that have been deallocated for more than 30 days or are in 
"Stopped (not deallocated)" state. Calculate the monthly waste for each.
```

### What to verify:
- [ ] Agent executes `az graph query` for VM discovery
- [ ] Agent calls `az advisor recommendation list --category Cost`
- [ ] Agent looks up SKU capabilities with `az vm list-skus`
- [ ] Agent runs KQL queries for P99 metrics
- [ ] FitScore calculation matches expected values (compare with `tests/test_fitscore.py`)
- [ ] Output follows `Recommendation-Format.md` schema
- [ ] Report includes severity classification and savings estimates

---

## Step 6 — Create the Scheduled Task

1. In your SRE Agent, select the **Scheduled tasks** tab
2. Click **Create scheduled task**
3. Fill in using `subagents/compute-optimization/schedule.yaml`:

| Field | Value |
|-------|-------|
| **Name** | `Weekly Compute Optimization Scan` |
| **Description** | `Run weekly compute optimization analysis across all accessible subscriptions. Identifies VM rightsizing opportunities with FitScore validation, detects idle/orphaned compute resources, and checks high availability configuration.` |
| **When should this task run?** | `Every Monday at 6 AM UTC` |
| **How often should it run?** | `Weekly` (or click "Draft the cron for me") |
| **Cron expression** | `0 6 * * 1` |
| **Agent instructions** | Copy the full `prompt` block from schedule.yaml (the 7-step workflow description) |
| **Max executions** | Leave blank for unlimited, or set to 52 (1 year of weekly runs) |

4. Click **Create scheduled task**

---

## Step 7 — Monitor and Validate

### Check the first run

After the scheduled task runs (or after a playground test):

1. Go to **Application Insights** (auto-created with the SRE Agent)
2. Look for:
   - Tool call traces (RunAzCliReadCommands, ExecutePythonCode)
   - FitScore calculation logs
   - Report delivery via UploadKnowledgeDocument

### Compare with simulation

Run the local simulation and compare outputs:

```bash
python tests/simulate_e2e.py
```

The simulation produces the same recommendation format, tool call sequence, and
FitScore calculations that the real agent will generate. Use it as a baseline.

### Validate FitScore accuracy

```bash
python tests/test_fitscore.py -v
```

All 15 test cases should pass. Compare the real agent's FitScore outputs against
these known-good values.

---

## Phase 2 — Add Remaining Subagents

Once the compute subagent is validated, repeat Steps 4-6 for each Phase 2 subagent:

| Order | Subagent | YAML Source | Schedule |
|-------|----------|-------------|----------|
| 1 | Storage Optimization Specialist | `subagents/storage-optimization/subagent.yaml` | Mon 07:00 UTC |
| 2 | Network Optimization Specialist | `subagents/network-optimization/subagent.yaml` | Mon 08:00 UTC |
| 3 | PaaS Optimization Specialist | `subagents/paas-optimization/subagent.yaml` | Mon 09:00 UTC |
| 4 | Governance & Compliance Specialist | `subagents/governance-compliance/subagent.yaml` | Mon 10:00 UTC |
| 5 | Orchestrator / Coordinator | `subagents/orchestrator/subagent.yaml` | Mon 11:00 UTC |

> **Important**: The Orchestrator runs LAST (11:00 UTC) because it aggregates
> reports from all specialist subagents. Configure its **Handoff Agents** to
> include all 5 specialist subagents.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "No data" in KQL queries | VM Insights / AMA not installed | Install Azure Monitor Agent on target VMs |
| Empty Advisor results | Advisor needs 7+ days of data | Wait for Advisor to generate recommendations |
| SKU lookup returns empty | Region doesn't have the SKU | Check SKU availability with `az vm list-skus --location <region>` |
| Email not sent | Outlook connector not configured, or known delivery bug | Configure Outlook connector in **Settings > Connectors**. If still failing, report is saved to KB as fallback ([sre-agent#67](https://github.com/microsoft/sre-agent/issues/67)) |
| FitScore always 5.0 | All metrics below thresholds | This is correct — means the resize is safe |
| Memory metrics missing | No VM Insights / AMA agent | FitScore deducts 0.5 automatically and notes the gap |
| Agent hangs after approving action | Az CLI command failing silently inside agent | Start a new conversation thread. Commands may work outside the agent but hang inside it ([sre-agent#53](https://github.com/microsoft/sre-agent/issues/53)) |
| "Internal error" in chat | Orphaned tool call in conversation history | Start a NEW thread. Do not retry in the same conversation ([sre-agent#51](https://github.com/microsoft/sre-agent/issues/51)) |
| User A works but User B is blocked | User-specific RBAC inconsistency in SRE Agent | Verify both users have identical roles AND are listed in SRE Agent access settings. Even with correct RBAC, agent may behave differently per user ([sre-agent#55](https://github.com/microsoft/sre-agent/issues/55)) |
| `BuildingKnowledgeGraph` stuck | Agent initialization can take 10–30+ min, may require `SecurityControl: Ignore` tag | Add tag `SecurityControl=Ignore` to agent resource. If still stuck after 30 min, delete and recreate the agent |
| Portal page won't load | Agent not in `Running` state | Check `properties.runningState` via REST API. Must be `Running` before portal works |
| Tools missing in incident response | Not all tools available in all contexts | Use subagent builder instead of Custom Incident Response for full tool access ([sre-agent#60](https://github.com/microsoft/sre-agent/issues/60)) |
| False "pending approvals" error | Agent UI bug after approving actions | Refresh the page and try again ([sre-agent#57](https://github.com/microsoft/sre-agent/issues/57)) |

---

## Known Issues (as of Feb 2026)

These are tracked in [microsoft/sre-agent](https://github.com/microsoft/sre-agent/issues) and affect our subagent:

| # | Issue | Impact on Us | Workaround |
|---|-------|-------------|------------|
| [#67](https://github.com/microsoft/sre-agent/issues/67) | Scheduled email tasks don't deliver | Weekly report email may not arrive | Report saved to KB as fallback + output in chat |
| [#53](https://github.com/microsoft/sre-agent/issues/53) | Az CLI commands hang after approval | `RunAzCliReadCommands` may time out | Instructions include skip-and-continue logic |
| [#55](https://github.com/microsoft/sre-agent/issues/55) | RBAC works for User A but not User B | Different users may get different results | Verify both portal RBAC and agent access settings |
| [#51](https://github.com/microsoft/sre-agent/issues/51) | Internal error from orphaned tool calls | Conversation becomes unusable | Fixed Feb 2026, but start new thread if it recurs |
| [#60](https://github.com/microsoft/sre-agent/issues/60) | Missing tools in Incident Response Plans | Some tools may be unavailable in certain contexts | Use subagent builder (has full tool access) |
| [#58](https://github.com/microsoft/sre-agent/issues/58) | No docs on subagent vs meta agent vs skills | Unclear when to use each construct | We use subagents (most flexible for custom workflows) |
| [#61](https://github.com/microsoft/sre-agent/issues/61) | Agent auto-triggers infrastructure scans | Unexpected resource scans may run | Monitor agent activity in Application Insights |

---

## Architecture Flow

```
┌─────────────────────────────────────────────────────────┐
│                  Azure SRE Agent                        │
│                                                         │
│  ┌─────────────────┐    ┌─────────────────────────────┐ │
│  │  Scheduled Task  │───→│  Compute Optimization       │ │
│  │  (Mon 6AM UTC)   │    │  Specialist Subagent        │ │
│  └─────────────────┘    │                             │ │
│                          │  Step 1: az graph query     │ │
│  ┌─────────────────┐    │  Step 2: Classify VMs       │ │
│  │  Knowledge Base  │───→│  Step 3: az advisor list    │ │
│  │  (10 .md files)  │    │  Step 4: FitScore (KQL+SKU)│ │
│  └─────────────────┘    │  Step 5: Idle detection     │ │
│                          │  Step 6: HA checks          │ │
│  ┌─────────────────┐    │  Step 7: Retail Prices API  │ │
│  │  Managed Identity│───▶│  Step 8: Report + KB save   │ │
│  │  (Reader + Mon.) │    └─────────────────────────────┘ │
│  └─────────────────┘                                    │
│                                                         │
│  Tools: RunAzCliReadCommands, ExecutePythonCode,         │
│         UploadKnowledgeDocument, GetActivityLogsSummary,  │
│         GetArmResourceAsJson, GetDimensionNames           │
└─────────────────────────────────────────────────────────┘
         │                    │                  │
         ▼                    ▼                  ▼
  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐
  │ Azure Monitor │  │ Azure Advisor│  │ Retail Prices API│
  │ (P99 metrics) │  │ (Cost recs)  │  │ (USD pricing)    │
  └──────────────┘  └──────────────┘  └──────────────────┘
```
