#!/bin/bash
# deploy-sre-agent.sh
# Provisions an Azure SRE Agent and configures it for optimization subagents.
#
# Prerequisites:
#   - Azure CLI installed and logged in (az login)
#   - SRE Agent Preview access enabled on subscription
#   - Sufficient permissions (Contributor on resource group)
#
# Usage:
#   chmod +x deploy-sre-agent.sh
#   ./deploy-sre-agent.sh -g <resource-group> -l <location> -n <agent-name>

set -euo pipefail

# ─── Defaults ───────────────────────────────────────────────────────
RESOURCE_GROUP=""
LOCATION="swedencentral"
AGENT_NAME="sre-optimization-agent"
SUBSCRIPTION=""

# ─── Parse arguments ────────────────────────────────────────────────
while getopts "g:l:n:s:" opt; do
  case $opt in
    g) RESOURCE_GROUP="$OPTARG" ;;
    l) LOCATION="$OPTARG" ;;
    n) AGENT_NAME="$OPTARG" ;;
    s) SUBSCRIPTION="$OPTARG" ;;
    *) echo "Usage: $0 -g <resource-group> -l <location> -n <agent-name> [-s <subscription>]"; exit 1 ;;
  esac
done

if [ -z "$RESOURCE_GROUP" ]; then
  echo "Error: Resource group (-g) is required."
  echo "Usage: $0 -g <resource-group> -l <location> -n <agent-name> [-s <subscription>]"
  exit 1
fi

# ─── Set subscription if provided ───────────────────────────────────
if [ -n "$SUBSCRIPTION" ]; then
  echo "Setting subscription to: $SUBSCRIPTION"
  az account set --subscription "$SUBSCRIPTION"
fi

CURRENT_SUB=$(az account show --query id -o tsv)
echo "Using subscription: $CURRENT_SUB"

# ─── Create resource group if it doesn't exist ──────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Step 1: Resource Group"
echo "═══════════════════════════════════════════════════════════"

if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
  echo "Resource group '$RESOURCE_GROUP' already exists."
else
  echo "Creating resource group '$RESOURCE_GROUP' in '$LOCATION'..."
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
  echo "Resource group created."
fi

# ─── Create SRE Agent ────────────────────────────────────────────────
 echo ""
echo "═════════════════════════════════════════════════════════"
echo "  Step 2: SRE Agent (via ARM REST API)"
echo "═════════════════════════════════════════════════════════"
echo ""
echo "Creating SRE Agent via ARM REST API..."
echo "  Resource type: Microsoft.App/agents"
echo "  API version: 2025-05-01-preview"
echo ""

# Create the ARM body as a temp file (avoids PowerShell/bash quoting issues)
cat > /tmp/sre-agent-body.json <<EOF
{
  "location": "$LOCATION",
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
  --url "https://management.azure.com/subscriptions/$CURRENT_SUB/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.App/agents/$AGENT_NAME?api-version=2025-05-01-preview" \
  --headers "Content-Type=application/json" \
  --body @/tmp/sre-agent-body.json

echo ""
echo "Waiting for provisioning to complete..."
for i in $(seq 1 30); do
  STATE=$(az rest --method GET \
    --url "https://management.azure.com/subscriptions/$CURRENT_SUB/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.App/agents/$AGENT_NAME?api-version=2025-05-01-preview" \
    --query "properties.provisioningState" -o tsv 2>/dev/null)
  echo "  [$i] provisioningState: $STATE"
  if [ "$STATE" = "Succeeded" ]; then
    echo "SRE Agent provisioned successfully."
    break
  fi
  sleep 10
done

echo ""
echo "Waiting for knowledge graph to build (runningState)..."
echo "This can take 10-30 minutes. Check portal once state is 'Running'."
for i in $(seq 1 60); do
  RSTATE=$(az rest --method GET \
    --url "https://management.azure.com/subscriptions/$CURRENT_SUB/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.App/agents/$AGENT_NAME?api-version=2025-05-01-preview" \
    --query "properties.runningState" -o tsv 2>/dev/null)
  echo "  [$i] runningState: $RSTATE"
  if [ "$RSTATE" = "Running" ]; then
    echo "SRE Agent is RUNNING. Portal is ready."
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo ""
    echo "WARNING: Agent still in '$RSTATE' after 30 minutes."
    echo "Consider deleting and recreating the agent."
    echo "If stuck on BuildingKnowledgeGraph, add SecurityControl=Ignore tag."
  fi
  sleep 30
done
echo "  - Managed Identity"
echo ""

# ─── Capture Managed Identity (after creation) ──────────────────────
echo "═══════════════════════════════════════════════════════════"
echo "  Step 3: Configure RBAC"
echo "═══════════════════════════════════════════════════════════"
echo ""

PRINCIPAL_ID=$(az rest --method GET \
  --url "https://management.azure.com/subscriptions/$CURRENT_SUB/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.App/agents/$AGENT_NAME?api-version=2025-05-01-preview" \
  --query "identity.principalId" -o tsv 2>/dev/null)

if [ -n "$PRINCIPAL_ID" ] && [ "$PRINCIPAL_ID" != "null" ]; then
  echo "Managed Identity Principal ID: $PRINCIPAL_ID"
  echo ""
  echo "Assigning RBAC roles..."

  az role assignment create --assignee "$PRINCIPAL_ID" \
    --role "Reader" --scope "/subscriptions/$CURRENT_SUB" --output none 2>/dev/null
  echo "  ✓ Reader"

  az role assignment create --assignee "$PRINCIPAL_ID" \
    --role "Monitoring Reader" --scope "/subscriptions/$CURRENT_SUB" --output none 2>/dev/null
  echo "  ✓ Monitoring Reader"

  az role assignment create --assignee "$PRINCIPAL_ID" \
    --role "Log Analytics Reader" --scope "/subscriptions/$CURRENT_SUB" --output none 2>/dev/null
  echo "  ✓ Log Analytics Reader"

  echo ""
  echo "RBAC configured. Note: If User A works but User B is blocked"
  echo "with the same roles, this is a known SRE Agent issue (ref: sre-agent#55)."
  echo "Both portal RBAC and agent-level access settings must match."
else
  echo "WARNING: Could not retrieve Managed Identity. Agent may still be provisioning."
  echo "Run setup-rbac.sh manually after agent is ready:"
  echo "  ./setup-rbac.sh -g $RESOURCE_GROUP -n $AGENT_NAME -s $CURRENT_SUB"
fi

# ─── Upload Knowledge Base ──────────────────────────────────────────
echo "═══════════════════════════════════════════════════════════"
echo "  Step 4: Upload Knowledge Base Documents"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Upload all files from the knowledge-base/ directory to the"
echo "SRE Agent's knowledge base via the Azure Portal:"
echo ""
echo "Files to upload:"
for f in ../knowledge-base/*.md; do
  echo "  - $(basename "$f")"
done
echo ""

# ─── Create Subagents ───────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════════"
echo "  Step 5: Create Subagents"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Create the following subagents in the SRE Agent portal:"
echo ""
echo "Phase 1 (PoC):"
echo "  1. Compute Optimization Specialist"
echo "     → Use: subagents/compute-optimization/subagent.yaml"
echo ""
echo "Phase 2:"
echo "  2. Storage Optimization Specialist"
echo "  3. Network Optimization Specialist"
echo "  4. PaaS Optimization Specialist"
echo "  5. Governance & Compliance Specialist"
echo "  6. Orchestrator / Coordinator"
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "  Deployment guide complete."
echo "═══════════════════════════════════════════════════════════"
