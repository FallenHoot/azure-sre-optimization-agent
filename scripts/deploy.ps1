<#
.SYNOPSIS
    Deploys the SRE Optimization Engine agent using Bicep.

.DESCRIPTION
    End-to-end deployment script that:
    1. Validates prerequisites (Azure CLI, Bicep, logged in)
    2. Deploys the Bicep template (creates RG, identity, App Insights, Log Analytics, agent)
    3. Waits for the knowledge graph to finish building
    4. Prints portal URL and next steps (subagent creation from subagent.yaml)

.PARAMETER ParametersFile
    Path to the Bicep parameters JSON file. Default: infra/main.parameters.json

.PARAMETER Location
    Azure region override. Default: uses value from parameters file.

.PARAMETER WaitForRunning
    Whether to poll until runningState = Running. Default: true

.PARAMETER MaxWaitMinutes
    Maximum time to wait for knowledge graph build. Default: 30

.EXAMPLE
    .\deploy.ps1
    .\deploy.ps1 -ParametersFile .\infra\examples\multi-rg.parameters.json
    .\deploy.ps1 -Location swedencentral -MaxWaitMinutes 45
#>

[CmdletBinding()]
param(
    [string]$ParametersFile = "",
    [string]$Location = "",
    [bool]$WaitForRunning = $true,
    [int]$MaxWaitMinutes = 30
)

$ErrorActionPreference = "Stop"

# ─── Paths ───────────────────────────────────────────────────────────────────
$scriptDir = $PSScriptRoot
$repoRoot  = Split-Path $scriptDir -Parent
$infraDir  = Join-Path $repoRoot "infra"

if (-not $ParametersFile) {
    $ParametersFile = Join-Path $infraDir "main.parameters.json"
}
$templateFile = Join-Path $infraDir "main.bicep"

# ─── Banner ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  SRE Optimization Engine — Bicep Deployment" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ─── Step 0: Validate prerequisites ─────────────────────────────────────────
Write-Host "[0/5] Validating prerequisites..." -ForegroundColor Yellow

# Azure CLI
if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI is not installed. Install from https://aka.ms/installazurecli"
    exit 1
}

# Bicep
$bicepVersion = az bicep version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Installing Bicep CLI..." -ForegroundColor Gray
    az bicep install
}
Write-Host "  ✓ Azure CLI + Bicep available" -ForegroundColor Green

# Logged in
$account = az account show -o json 2>&1 | ConvertFrom-Json
if (-not $account.id) {
    Write-Error "Not logged in. Run 'az login' first."
    exit 1
}
Write-Host "  ✓ Logged in as: $($account.user.name)" -ForegroundColor Green
Write-Host "  ✓ Subscription: $($account.name) ($($account.id))" -ForegroundColor Green

# Microsoft.App provider
$provider = az provider show --namespace Microsoft.App --query "registrationState" -o tsv 2>&1
if ($provider -ne "Registered") {
    Write-Host "  Registering Microsoft.App provider..." -ForegroundColor Gray
    az provider register --namespace Microsoft.App
    Write-Host "  Waiting for registration (up to 2 min)..." -ForegroundColor Gray
    for ($i = 0; $i -lt 24; $i++) {
        Start-Sleep -Seconds 5
        $state = az provider show --namespace Microsoft.App --query "registrationState" -o tsv 2>&1
        if ($state -eq "Registered") { break }
    }
}
Write-Host "  ✓ Microsoft.App provider registered" -ForegroundColor Green

# Template + params files exist
if (-not (Test-Path $templateFile)) {
    Write-Error "Template file not found: $templateFile"
    exit 1
}
if (-not (Test-Path $ParametersFile)) {
    Write-Error "Parameters file not found: $ParametersFile"
    exit 1
}
Write-Host "  ✓ Template: $templateFile" -ForegroundColor Green
Write-Host "  ✓ Params:   $ParametersFile" -ForegroundColor Green

# ─── Step 1: Validate Bicep ─────────────────────────────────────────────────
Write-Host ""
Write-Host "[1/5] Validating Bicep template..." -ForegroundColor Yellow

az bicep build --file $templateFile --outfile "$env:TEMP\sre-agent-compiled.json" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Bicep validation failed. Fix errors above."
    exit 1
}
Remove-Item "$env:TEMP\sre-agent-compiled.json" -ErrorAction SilentlyContinue
Write-Host "  ✓ Bicep template is valid" -ForegroundColor Green

# ─── Step 2: Read parameters for summary ────────────────────────────────────
$params = (Get-Content $ParametersFile -Raw | ConvertFrom-Json).parameters
$agentName = $params.agentName.value
$rgName = $params.resourceGroupName.value
$deployLocation = if ($Location) { $Location } else { $params.location.value }
$accessLevel = $params.accessLevel.value
$agentMode = $params.agentMode.value

Write-Host ""
Write-Host "[2/5] Deployment configuration:" -ForegroundColor Yellow
Write-Host "  Agent Name:     $agentName" -ForegroundColor White
Write-Host "  Resource Group: $rgName" -ForegroundColor White
Write-Host "  Location:       $deployLocation" -ForegroundColor White
Write-Host "  Access Level:   $accessLevel" -ForegroundColor White
Write-Host "  Agent Mode:     $agentMode" -ForegroundColor White
Write-Host "  Subscription:   $($account.id)" -ForegroundColor White
Write-Host ""

$confirm = Read-Host "  Proceed with deployment? (y/N)"
if ($confirm -notmatch "^[Yy]") {
    Write-Host "Deployment cancelled." -ForegroundColor Yellow
    exit 0
}

# ─── Step 3: Deploy ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[3/5] Deploying SRE Agent infrastructure..." -ForegroundColor Yellow

$deploymentName = "sre-agent-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$deployArgs = @(
    "deployment", "sub", "create",
    "--name", $deploymentName,
    "--location", $deployLocation,
    "--template-file", $templateFile,
    "--parameters", "@$ParametersFile"
)

# Add location override if specified
if ($Location) {
    $deployArgs += @("--parameters", "location=$Location")
}

$deployOutput = az @deployArgs -o json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host $deployOutput -ForegroundColor Red
    Write-Error "Deployment failed. See errors above."
    exit 1
}

$outputs = ($deployOutput | ConvertFrom-Json).properties.outputs
$agentEndpoint = $outputs.agentEndpoint.value
$portalUrl = $outputs.portalUrl.value
$uaIdentityId = $outputs.userAssignedIdentityId.value
$uaPrincipalId = $outputs.userAssignedIdentityPrincipalId.value

Write-Host "  ✓ Deployment succeeded!" -ForegroundColor Green
Write-Host "  Agent Endpoint: $agentEndpoint" -ForegroundColor Cyan
Write-Host "  UA Identity:    $uaPrincipalId" -ForegroundColor Cyan

# ─── Step 4: Wait for knowledge graph ───────────────────────────────────────
if ($WaitForRunning) {
    Write-Host ""
    Write-Host "[4/5] Waiting for knowledge graph build..." -ForegroundColor Yellow
    Write-Host "  This typically takes 5-15 minutes." -ForegroundColor Gray

    $agentUri = "https://management.azure.com$($outputs.agentResourceId.value)?api-version=2025-05-01-preview"
    $startTime = Get-Date
    $maxWait = New-TimeSpan -Minutes $MaxWaitMinutes

    for ($i = 1; ; $i++) {
        Start-Sleep -Seconds 30
        $state = az rest --method GET --uri $agentUri --query "properties.runningState" -o tsv 2>&1

        $elapsed = (Get-Date) - $startTime
        $elapsedMin = [math]::Round($elapsed.TotalMinutes, 1)

        if ($state -eq "Running") {
            Write-Host "  ✓ Agent is RUNNING! (after $elapsedMin min)" -ForegroundColor Green
            break
        }

        Write-Host "  [$i] runningState: $state ($elapsedMin min elapsed)" -ForegroundColor Gray

        if ($elapsed -gt $maxWait) {
            Write-Host ""
            Write-Host "  ⚠ Agent still in '$state' after $MaxWaitMinutes minutes." -ForegroundColor Yellow
            Write-Host "    This may be normal — some agents take up to 30 min." -ForegroundColor Yellow
            Write-Host "    Check the portal URL below, or re-run this script later." -ForegroundColor Yellow
            break
        }
    }
} else {
    Write-Host ""
    Write-Host "[4/5] Skipping knowledge graph wait (--WaitForRunning=false)" -ForegroundColor Gray
}

# ─── Step 5: Next steps ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "[5/5] Deployment complete!" -ForegroundColor Green
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  NEXT STEPS" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Open the SRE Agent Portal:" -ForegroundColor White
Write-Host "     $portalUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "  2. Deploy all subagents:" -ForegroundColor White
Write-Host "     .\deploy-subagents.ps1 -ResourceGroup $rgName" -ForegroundColor Cyan
Write-Host "     This will attempt REST API creation and generate" -ForegroundColor Gray
Write-Host "     portal-paste files for manual creation if needed." -ForegroundColor Gray
Write-Host "     Subagent configs: subagents/*/subagent.yaml" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. Upload knowledge base documents:" -ForegroundColor White
$kbDir = Join-Path $repoRoot "knowledge-base"
if (Test-Path $kbDir) {
    Get-ChildItem $kbDir -Filter "*.md" | ForEach-Object {
        Write-Host "     • $($_.Name)" -ForegroundColor Gray
    }
}
Write-Host ""
Write-Host "  4. Create scheduled tasks (optional):" -ForegroundColor White
Write-Host "     • Schedule → Create for each subagent" -ForegroundColor Gray
Write-Host "     • Compute Mon 06:00, Storage 07:00, Network 08:00" -ForegroundColor Gray
Write-Host "     • PaaS 09:00, Governance 10:00, Orchestrator 11:00" -ForegroundColor Gray
Write-Host "     • See subagents/*/schedule.yaml for details" -ForegroundColor Gray
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Resources created in $rgName :" -ForegroundColor Cyan
Write-Host "    • SRE Agent:           $agentName" -ForegroundColor White
Write-Host "    • User-Assigned MI:    $(Split-Path $uaIdentityId -Leaf)" -ForegroundColor White
Write-Host "    • App Insights:        $($outputs.applicationInsightsName.value)" -ForegroundColor White
Write-Host "    • Log Analytics:       $(Split-Path $outputs.logAnalyticsWorkspaceId.value -Leaf)" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
