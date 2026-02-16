#!/bin/bash
# setup-rbac.sh
# Grants the SRE Agent's Managed Identity the required RBAC roles
# for all optimization subagents to function.
#
# Prerequisites:
#   - SRE Agent already created (Managed Identity exists)
#   - Azure CLI logged in with Owner or User Access Administrator role
#
# Usage:
#   chmod +x setup-rbac.sh
#   ./setup-rbac.sh -g <resource-group> -n <agent-name> -s <subscription-id> [-t <tenant-id>]

set -euo pipefail

RESOURCE_GROUP=""
AGENT_NAME=""
SUBSCRIPTION=""
TENANT_ID=""
ADDITIONAL_SUBS=()

while getopts "g:n:s:t:a:" opt; do
  case $opt in
    g) RESOURCE_GROUP="$OPTARG" ;;
    n) AGENT_NAME="$OPTARG" ;;
    s) SUBSCRIPTION="$OPTARG" ;;
    t) TENANT_ID="$OPTARG" ;;
    a) IFS=',' read -ra ADDITIONAL_SUBS <<< "$OPTARG" ;;
    *) echo "Usage: $0 -g <rg> -n <agent-name> -s <sub-id> [-t <tenant-id>] [-a <sub1,sub2>]"; exit 1 ;;
  esac
done

if [ -z "$RESOURCE_GROUP" ] || [ -z "$AGENT_NAME" ] || [ -z "$SUBSCRIPTION" ]; then
  echo "Error: Resource group (-g), agent name (-n), and subscription (-s) are required."
  exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  RBAC Setup for SRE Agent Optimization Subagents"
echo "═══════════════════════════════════════════════════════════"
echo ""

# ─── Get Managed Identity Principal ID ──────────────────────────────
echo "Looking up Managed Identity for SRE Agent: $AGENT_NAME..."
echo ""
echo "NOTE: You may need to find the Managed Identity manually."
echo "      Check the SRE Agent resource in the Azure Portal"
echo "      → Identity → System assigned → Object (principal) ID"
echo ""
read -p "Enter the Managed Identity Object (Principal) ID: " PRINCIPAL_ID

if [ -z "$PRINCIPAL_ID" ]; then
  echo "Error: Principal ID is required."
  exit 1
fi

echo ""
echo "Using Principal ID: $PRINCIPAL_ID"
echo ""

# ─── Assign roles on primary subscription ───────────────────────────
echo "═══════════════════════════════════════════════════════════"
echo "  Assigning roles on subscription: $SUBSCRIPTION"
echo "═══════════════════════════════════════════════════════════"

assign_role() {
  local role="$1"
  local scope="$2"
  local description="$3"
  
  echo -n "  Assigning '$role'... "
  if az role assignment create \
    --assignee-object-id "$PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "$role" \
    --scope "$scope" \
    --output none 2>/dev/null; then
    echo "✅ Done"
  else
    echo "⚠️  May already exist or insufficient permissions"
  fi
}

SUB_SCOPE="/subscriptions/$SUBSCRIPTION"

echo ""
echo "Required roles for optimization subagents:"
echo ""

# Reader — Resource Graph queries, resource enumeration
assign_role "Reader" "$SUB_SCOPE" "Resource Graph queries, resource enumeration"

# Monitoring Reader — Azure Monitor metrics access
assign_role "Monitoring Reader" "$SUB_SCOPE" "Azure Monitor metrics access"

# Log Analytics Reader — KQL queries against Log Analytics workspaces
assign_role "Log Analytics Reader" "$SUB_SCOPE" "Log Analytics workspace queries"

echo ""

# ─── Assign roles on additional subscriptions ───────────────────────
for sub in "${ADDITIONAL_SUBS[@]}"; do
  if [ -n "$sub" ]; then
    echo "═══════════════════════════════════════════════════════════"
    echo "  Assigning roles on additional subscription: $sub"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    
    ADDITIONAL_SCOPE="/subscriptions/$sub"
    assign_role "Reader" "$ADDITIONAL_SCOPE" "Resource Graph"
    assign_role "Monitoring Reader" "$ADDITIONAL_SCOPE" "Azure Monitor"
    assign_role "Log Analytics Reader" "$ADDITIONAL_SCOPE" "Log Analytics"
    echo ""
  fi
done

# ─── Directory Reader (for Governance subagent) ──────────────────────
echo "═══════════════════════════════════════════════════════════"
echo "  Microsoft Entra ID Role (for Governance subagent)"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "The Governance & Compliance subagent needs 'Directory Reader'"
echo "role in Microsoft Entra ID to check app registration credentials."
echo ""
echo "This must be assigned by a Global Administrator or Privileged"
echo "Role Administrator in the Azure Portal:"
echo ""
echo "  1. Go to Microsoft Entra ID → Roles and administrators"
echo "  2. Find 'Directory Readers'"
echo "  3. Add assignment → Select: $PRINCIPAL_ID"
echo ""

# ─── Summary ─────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════════"
echo "  RBAC Setup Summary"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  Principal ID:      $PRINCIPAL_ID"
echo "  Primary sub:       $SUBSCRIPTION"
echo "  Additional subs:   ${ADDITIONAL_SUBS[*]:-none}"
echo ""
echo "  Roles assigned:"
echo "    ✅ Reader (subscription scope)"
echo "    ✅ Monitoring Reader (subscription scope)"
echo "    ✅ Log Analytics Reader (subscription scope)"
echo "    ⚠️  Directory Reader (requires manual Entra ID assignment)"
echo ""
echo "  Run validate-access.sh to verify all APIs are accessible."
echo ""
