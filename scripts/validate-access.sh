#!/bin/bash
# validate-access.sh
# Verifies that the SRE Agent's Managed Identity (or current CLI session)
# can access all APIs required by the optimization subagents.
#
# Usage:
#   chmod +x validate-access.sh
#   ./validate-access.sh [-s <subscription-id>]

set -euo pipefail

SUBSCRIPTION=""

while getopts "s:" opt; do
  case $opt in
    s) SUBSCRIPTION="$OPTARG" ;;
    *) echo "Usage: $0 [-s <subscription-id>]"; exit 1 ;;
  esac
done

if [ -n "$SUBSCRIPTION" ]; then
  az account set --subscription "$SUBSCRIPTION"
fi

CURRENT_SUB=$(az account show --query id -o tsv)
CURRENT_SUB_NAME=$(az account show --query name -o tsv)

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  API Access Validation"
echo "  Subscription: $CURRENT_SUB_NAME ($CURRENT_SUB)"
echo "═══════════════════════════════════════════════════════════"
echo ""

PASS=0
FAIL=0
WARN=0

check() {
  local name="$1"
  local cmd="$2"
  echo -n "  [$name] "
  if eval "$cmd" &>/dev/null; then
    echo "✅ PASS"
    ((PASS++))
  else
    echo "❌ FAIL"
    ((FAIL++))
  fi
}

check_warn() {
  local name="$1"
  local cmd="$2"
  echo -n "  [$name] "
  if eval "$cmd" &>/dev/null; then
    echo "✅ PASS"
    ((PASS++))
  else
    echo "⚠️  WARN (optional)"
    ((WARN++))
  fi
}

# ─── Azure Resource Graph ───────────────────────────────────────────
echo "── Azure Resource Graph ──────────────────────────────────"
check "List VMs via Resource Graph" \
  "az graph query -q \"Resources | where type =~ 'microsoft.compute/virtualMachines' | limit 1\" --output json"

check "List Disks via Resource Graph" \
  "az graph query -q \"Resources | where type =~ 'microsoft.compute/disks' | limit 1\" --output json"

check "List Load Balancers via Resource Graph" \
  "az graph query -q \"Resources | where type =~ 'microsoft.network/loadBalancers' | limit 1\" --output json"

echo ""

# ─── Azure Advisor ──────────────────────────────────────────────────
echo "── Azure Advisor ─────────────────────────────────────────"
check "List Advisor Cost Recommendations" \
  "az advisor recommendation list --category Cost --output json"

echo ""

# ─── Compute Resource SKUs ──────────────────────────────────────────
echo "── Compute Resource SKUs ─────────────────────────────────"
check "List VM SKUs (swedencentral)" \
  "az vm list-skus --location swedencentral --size Standard_D4s_v5 --output json"

echo ""

# ─── Azure Monitor ──────────────────────────────────────────────────
echo "── Azure Monitor ─────────────────────────────────────────"
echo "  Note: Monitor metric queries require a specific resource ID."
echo "  Checking if az monitor is accessible..."
check "Azure Monitor CLI available" \
  "az monitor --help"

echo ""

# ─── Azure Retail Prices (public, no auth) ──────────────────────────
echo "── Azure Retail Prices API ───────────────────────────────"
check "Retail Prices API accessible" \
  "curl -s 'https://prices.azure.com/api/retail/prices?\$top=1' | head -c 100"

echo ""

# ─── Microsoft Graph (for Governance subagent) ──────────────────────
echo "── Microsoft Graph (optional — Governance subagent) ─────"
check_warn "List App Registrations" \
  "az ad app list --query '[].{id:id}' --output json --top 1"

echo ""

# ─── Activity Log (for deallocated VM age detection) ────────────────
echo "── Activity Log ──────────────────────────────────────────"
check "Activity Log accessible" \
  "az monitor activity-log list --offset 1d --max-events 1 --output json"

echo ""

# ─── Summary ─────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════════"
echo "  Validation Summary"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  ✅ Passed:  $PASS"
echo "  ❌ Failed:  $FAIL"
echo "  ⚠️  Warned: $WARN"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "  Some checks failed. Run setup-rbac.sh to fix permissions."
  exit 1
else
  echo "  All required APIs are accessible. Ready to deploy subagents!"
  exit 0
fi
