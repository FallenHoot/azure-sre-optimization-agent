<#
.SYNOPSIS
    Deploys all subagents to an existing Azure SRE Agent.

.DESCRIPTION
    This script automates subagent deployment as much as the SRE Agent
    platform allows:

    Phase 1 — Discovers the SRE Agent resource and validates access.
    Phase 2 — Attempts programmatic subagent creation via REST API
              (undocumented — may fail in preview).
    Phase 3 — Falls back to generating portal-ready paste blocks for
              manual creation via the Subagent Builder UI.
    Phase 4 — Uploads knowledge base documents programmatically.
    Phase 5 — Outputs scheduled task definitions for manual creation.

    NOTE: As of Feb 2026, subagent creation is portal-only in the SRE
    Agent preview. This script maximizes automation and minimizes the
    manual portal work to copy-paste operations.

.PARAMETER AgentResourceId
    Full ARM resource ID of the SRE Agent. If not provided, the script
    will attempt to discover it from the resource group.

.PARAMETER ResourceGroup
    Resource group containing the SRE Agent.

.PARAMETER SubscriptionId
    Azure subscription ID. Defaults to the current az CLI subscription.

.PARAMETER SubagentsDir
    Path to the subagents directory. Default: ../subagents

.PARAMETER KnowledgeBaseDir
    Path to the knowledge base directory. Default: ../knowledge-base

.PARAMETER SkipKnowledgeBase
    Skip knowledge base upload.

.PARAMETER OutputDir
    Directory for generated portal-paste files. Default: ../deploy-output

.EXAMPLE
    .\deploy-subagents.ps1 -ResourceGroup rg-sre-optimization
    .\deploy-subagents.ps1 -AgentResourceId "/subscriptions/.../agents/sre-optimization-agent"
#>

[CmdletBinding()]
param(
    [string]$AgentResourceId = "",
    [string]$ResourceGroup = "rg-sre-optimization",
    [string]$SubscriptionId = "",
    [string]$SubagentsDir = "",
    [string]$KnowledgeBaseDir = "",
    [switch]$SkipKnowledgeBase,
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

# ─── Paths ───────────────────────────────────────────────────────────────────
$scriptDir = $PSScriptRoot
$repoRoot  = Split-Path $scriptDir -Parent

if (-not $SubagentsDir)    { $SubagentsDir    = Join-Path $repoRoot "subagents" }
if (-not $KnowledgeBaseDir){ $KnowledgeBaseDir= Join-Path $repoRoot "knowledge-base" }
if (-not $OutputDir)       { $OutputDir       = Join-Path $repoRoot "deploy-output" }

# Ensure output dir exists
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

# ─── Banner ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  SRE Optimization Engine — Subagent Deployment" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ─── Helper: Parse YAML (lightweight, no module dependency) ──────────────────
function Parse-SubagentYaml {
    param([string]$FilePath)

    $content = Get-Content $FilePath -Raw
    $result = @{}

    # Extract top-level fields
    if ($content -match '(?m)^\s*name:\s*(.+)$')  {
        $result.Name = $Matches[1].Trim().Trim('"').Trim("'")
    }

    # Extract system_prompt (everything between system_prompt: | and the next
    # top-level key under spec:)
    if ($content -match '(?s)system_prompt:\s*\|\s*\n(.*?)(?=\n\s{2}\w+:)') {
        $result.SystemPrompt = $Matches[1]
    }

    # Extract handoff_description
    if ($content -match '(?s)handoff_description:\s*>\s*\n(.*?)(?=\n\s{2}\w+:)') {
        $result.HandoffDescription = $Matches[1].Trim() -replace '\s+', ' '
    }
    elseif ($content -match '(?m)handoff_description:\s*[''"]?(.+?)[''"]?\s*$') {
        $result.HandoffDescription = $Matches[1].Trim()
    }

    # Extract tools list
    $result.Tools = @()
    if ($content -match '(?s)tools:\s*\n((?:\s+-\s+\S+\n?)+)') {
        $toolsBlock = $Matches[1]
        $result.Tools = [regex]::Matches($toolsBlock, '-\s+(\S+)') |
            ForEach-Object { $_.Groups[1].Value.Trim('"').Trim("'") }
    }

    # Extract agent_type
    if ($content -match '(?m)agent_type:\s*(\S+)') {
        $result.AgentType = $Matches[1].Trim()
    }

    return $result
}

# ─── Phase 0: Validate prerequisites ────────────────────────────────────────
Write-Host "[0/5] Validating prerequisites..." -ForegroundColor Yellow

if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI is not installed."
    exit 1
}

$account = az account show -o json 2>&1 | ConvertFrom-Json
if (-not $account.id) {
    Write-Error "Not logged in. Run 'az login' first."
    exit 1
}
if (-not $SubscriptionId) { $SubscriptionId = $account.id }
Write-Host "  ✓ Logged in: $($account.user.name)" -ForegroundColor Green
Write-Host "  ✓ Subscription: $SubscriptionId" -ForegroundColor Green

# Discover subagent.yaml files
$subagentFiles = Get-ChildItem -Path $SubagentsDir -Recurse -Filter "subagent.yaml"
if ($subagentFiles.Count -eq 0) {
    Write-Error "No subagent.yaml files found in $SubagentsDir"
    exit 1
}
Write-Host "  ✓ Found $($subagentFiles.Count) subagent.yaml files" -ForegroundColor Green

# ─── Phase 1: Discover SRE Agent resource ───────────────────────────────────
Write-Host ""
Write-Host "[1/5] Discovering SRE Agent resource..." -ForegroundColor Yellow

if (-not $AgentResourceId) {
    # Find agents in the resource group
    $agents = az resource list --resource-group $ResourceGroup `
        --resource-type "Microsoft.App/agents" `
        --subscription $SubscriptionId `
        -o json 2>&1 | ConvertFrom-Json

    if ($agents -and $agents.Count -gt 0) {
        $AgentResourceId = $agents[0].id
        $agentName = $agents[0].name
        Write-Host "  ✓ Found agent: $agentName" -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠ No SRE Agent found in $ResourceGroup." -ForegroundColor Yellow
        Write-Host "    Run deploy.ps1 first to create the agent infrastructure." -ForegroundColor Yellow
        Write-Host "    Continuing in offline mode (portal-paste output only)." -ForegroundColor Yellow
        $AgentResourceId = ""
    }
}
else {
    $agentName = ($AgentResourceId -split '/')[-1]
    Write-Host "  ✓ Using agent: $agentName" -ForegroundColor Green
}

if ($AgentResourceId) {
    $agentApiUri = "https://management.azure.com${AgentResourceId}?api-version=2025-05-01-preview"
    $agentState = az rest --method GET --uri $agentApiUri --query "properties.runningState" -o tsv 2>&1
    Write-Host "  Agent state: $agentState" -ForegroundColor $(if ($agentState -eq "Running") { "Green" } else { "Yellow" })
}

# ─── Phase 2: Attempt programmatic subagent creation via REST ────────────────
Write-Host ""
Write-Host "[2/5] Attempting programmatic subagent creation..." -ForegroundColor Yellow

$restApiWorked = $false
$createdSubagents = @()
$failedSubagents = @()

if ($AgentResourceId) {
    foreach ($file in $subagentFiles) {
        $parsed = Parse-SubagentYaml -FilePath $file.FullName
        $subagentName = $parsed.Name -replace '\s+', '-'
        $dirName = $file.Directory.Name

        Write-Host "  Attempting: $($parsed.Name)..." -ForegroundColor Gray

        # Build the REST API body for subagent creation
        $body = @{
            properties = @{
                name = $parsed.Name
                instructions = $parsed.SystemPrompt
                handoffDescription = $parsed.HandoffDescription
                tools = $parsed.Tools
                agentType = ($parsed.AgentType ?? "Autonomous")
            }
        } | ConvertTo-Json -Depth 10 -Compress

        # Try the most likely child resource paths
        $apiPaths = @(
            "${AgentResourceId}/subagents/${subagentName}?api-version=2025-05-01-preview",
            "${AgentResourceId}/subAgents/${subagentName}?api-version=2025-05-01-preview",
            "${AgentResourceId}/children/${subagentName}?api-version=2025-05-01-preview"
        )

        $created = $false
        foreach ($apiPath in $apiPaths) {
            $uri = "https://management.azure.com${apiPath}"
            try {
                $response = az rest --method PUT --uri $uri --body $body -o json 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "    ✓ Created via REST API!" -ForegroundColor Green
                    $createdSubagents += $parsed.Name
                    $created = $true
                    $restApiWorked = $true
                    break
                }
            }
            catch {
                # Expected — API path doesn't exist yet
            }
        }

        if (-not $created) {
            $failedSubagents += @{ Name = $parsed.Name; Dir = $dirName; File = $file.FullName; Parsed = $parsed }
        }
    }

    if ($restApiWorked) {
        Write-Host ""
        Write-Host "  ✓ REST API creation succeeded for $($createdSubagents.Count) subagent(s)!" -ForegroundColor Green
    }
    else {
        Write-Host "  ℹ REST API not available for subagent creation (expected in preview)." -ForegroundColor Yellow
        Write-Host "    Generating portal-ready paste blocks instead." -ForegroundColor Yellow
    }
}
else {
    Write-Host "  Skipped (no agent resource discovered)." -ForegroundColor Gray
    foreach ($file in $subagentFiles) {
        $parsed = Parse-SubagentYaml -FilePath $file.FullName
        $failedSubagents += @{ Name = $parsed.Name; Dir = $file.Directory.Name; File = $file.FullName; Parsed = $parsed }
    }
}

# ─── Phase 3: Generate portal-ready paste blocks ────────────────────────────
Write-Host ""
Write-Host "[3/5] Generating portal-ready deployment files..." -ForegroundColor Yellow

$portalGuide = @()
$portalGuide += "# SRE Agent — Subagent Portal Deployment Guide"
$portalGuide += "# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
$portalGuide += ""
$portalGuide += "## Quick Start"
$portalGuide += "1. Open the Azure Portal → SRE Agent → Subagent Builder tab"
$portalGuide += "2. For each subagent below: Create → Subagent → paste the fields"
$portalGuide += "3. Select the listed tools from the Built-in Tools dropdown"
$portalGuide += "4. Save and test each subagent"
$portalGuide += ""

$subagentIndex = 0
foreach ($entry in $failedSubagents) {
    $subagentIndex++
    $parsed = $entry.Parsed
    $dirName = $entry.Dir

    Write-Host "  [$subagentIndex/$($failedSubagents.Count)] $($parsed.Name)" -ForegroundColor White

    # Write individual paste file for each subagent
    $pasteFile = Join-Path $OutputDir "${dirName}-portal-paste.md"
    $pasteContent = @()
    $pasteContent += "# $($parsed.Name) — Portal Paste Block"
    $pasteContent += ""
    $pasteContent += "## Field: Name"
    $pasteContent += "``````"
    $pasteContent += $parsed.Name
    $pasteContent += "``````"
    $pasteContent += ""
    $pasteContent += "## Field: Instructions"
    $pasteContent += "Paste the content below into the **Instructions** field:"
    $pasteContent += ""
    $pasteContent += "``````"
    $pasteContent += $parsed.SystemPrompt
    $pasteContent += "``````"
    $pasteContent += ""
    $pasteContent += "## Field: Handoff Description"
    $pasteContent += "``````"
    $pasteContent += $parsed.HandoffDescription
    $pasteContent += "``````"
    $pasteContent += ""
    $pasteContent += "## Built-in Tools (select these in the dropdown)"
    foreach ($tool in $parsed.Tools) {
        $pasteContent += "- [x] $tool"
    }
    $pasteContent += ""
    $pasteContent += "## Agent Type"
    $pasteContent += "Set to: **$($parsed.AgentType ?? 'Autonomous')**"
    $pasteContent += ""
    $pasteContent += "---"
    $pasteContent += "Source: subagents/$dirName/subagent.yaml"

    $pasteContent | Out-File -FilePath $pasteFile -Encoding utf8 -Force
    Write-Host "    → $pasteFile" -ForegroundColor Gray

    # Add to portal guide
    $portalGuide += "---"
    $portalGuide += ""
    $portalGuide += "### $subagentIndex. $($parsed.Name)"
    $portalGuide += "- **Source**: ``subagents/$dirName/subagent.yaml``"
    $portalGuide += "- **Portal paste file**: ``deploy-output/${dirName}-portal-paste.md``"
    $portalGuide += "- **Tools** ($($parsed.Tools.Count)): $($parsed.Tools -join ', ')"
    $portalGuide += "- **Type**: $($parsed.AgentType ?? 'Autonomous')"
    $portalGuide += ""
}

# Write the portal guide
$guideFile = Join-Path $OutputDir "PORTAL-DEPLOYMENT-GUIDE.md"
$portalGuide | Out-File -FilePath $guideFile -Encoding utf8 -Force
Write-Host ""
Write-Host "  ✓ Portal guide: $guideFile" -ForegroundColor Green

# ─── Phase 4: Upload knowledge base documents ───────────────────────────────
Write-Host ""
Write-Host "[4/5] Uploading knowledge base documents..." -ForegroundColor Yellow

if ($SkipKnowledgeBase) {
    Write-Host "  Skipped (--SkipKnowledgeBase flag)." -ForegroundColor Gray
}
elseif (-not (Test-Path $KnowledgeBaseDir)) {
    Write-Host "  Skipped (no knowledge-base directory found)." -ForegroundColor Gray
}
elseif (-not $AgentResourceId) {
    Write-Host "  Skipped (no agent resource — run deploy.ps1 first)." -ForegroundColor Gray
}
else {
    $kbFiles = Get-ChildItem -Path $KnowledgeBaseDir -Filter "*.md"
    if ($kbFiles.Count -eq 0) {
        Write-Host "  No .md files found in $KnowledgeBaseDir" -ForegroundColor Gray
    }
    else {
        $uploaded = 0
        $kbApiBase = "https://management.azure.com${AgentResourceId}"

        foreach ($kbFile in $kbFiles) {
            $docName = $kbFile.BaseName
            Write-Host "  Uploading: $($kbFile.Name)..." -ForegroundColor Gray

            # Read file content
            $fileContent = Get-Content $kbFile.FullName -Raw

            # Try uploading via the knowledge base API
            $kbBody = @{
                properties = @{
                    displayName = $docName
                    content = $fileContent
                    contentType = "text/markdown"
                }
            } | ConvertTo-Json -Depth 5 -Compress

            # Attempt known API paths for knowledge base upload
            $kbPaths = @(
                "${AgentResourceId}/knowledgeBase/documents/${docName}?api-version=2025-05-01-preview",
                "${AgentResourceId}/knowledgeDocuments/${docName}?api-version=2025-05-01-preview",
                "${AgentResourceId}/documents/${docName}?api-version=2025-05-01-preview"
            )

            $kbUploaded = $false
            foreach ($kbPath in $kbPaths) {
                $kbUri = "https://management.azure.com${kbPath}"
                try {
                    $kbResponse = az rest --method PUT --uri $kbUri --body $kbBody -o json 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "    ✓ Uploaded" -ForegroundColor Green
                        $uploaded++
                        $kbUploaded = $true
                        break
                    }
                }
                catch { }
            }

            if (-not $kbUploaded) {
                Write-Host "    ⚠ REST upload failed — upload manually via portal" -ForegroundColor Yellow
            }
        }

        if ($uploaded -gt 0) {
            Write-Host "  ✓ Uploaded $uploaded/$($kbFiles.Count) documents" -ForegroundColor Green
        }
        else {
            Write-Host "  ℹ KB REST API not available in preview — upload via portal:" -ForegroundColor Yellow
            Write-Host "    Settings → Knowledge Base → Files → drag and drop" -ForegroundColor Gray
            Write-Host "    Files to upload:" -ForegroundColor Gray
            foreach ($kbFile in $kbFiles) {
                Write-Host "      • $($kbFile.Name)" -ForegroundColor Gray
            }
        }
    }
}

# ─── Phase 5: Scheduled task definitions ─────────────────────────────────────
Write-Host ""
Write-Host "[5/5] Scheduled task summary..." -ForegroundColor Yellow

$scheduleFiles = Get-ChildItem -Path $SubagentsDir -Recurse -Filter "schedule.yaml"
if ($scheduleFiles.Count -gt 0) {
    Write-Host ""
    Write-Host "  Create these scheduled tasks in the portal (Schedule tab):" -ForegroundColor White
    Write-Host ""
    Write-Host "  ┌──────────────────────────────────────┬────────────────┬──────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "  │ Subagent                             │ Schedule (UTC) │ Source                           │" -ForegroundColor DarkGray
    Write-Host "  ├──────────────────────────────────────┼────────────────┼──────────────────────────────────┤" -ForegroundColor DarkGray

    $scheduleOrder = @(
        @{ Dir = "compute-optimization";  Name = "Compute-Optimization-Specialist";  Time = "Mon 06:00" },
        @{ Dir = "storage-optimization";  Name = "Storage-Optimization-Specialist";  Time = "Mon 07:00" },
        @{ Dir = "network-optimization";  Name = "Network-Optimization-Specialist";  Time = "Mon 08:00" },
        @{ Dir = "paas-optimization";     Name = "PaaS-Optimization-Specialist";     Time = "Mon 09:00" },
        @{ Dir = "governance-compliance"; Name = "Governance-Compliance-Specialist"; Time = "Mon 10:00" },
        @{ Dir = "orchestrator";          Name = "Orchestrator-Coordinator";         Time = "Mon 11:00" }
    )

    foreach ($sched in $scheduleOrder) {
        $nameCol = $sched.Name.PadRight(36)
        $timeCol = $sched.Time.PadRight(14)
        $srcCol  = "subagents/$($sched.Dir)/schedule.yaml"
        Write-Host "  │ $nameCol │ $timeCol │ $srcCol │" -ForegroundColor White
    }
    Write-Host "  └──────────────────────────────────────┴────────────────┴──────────────────────────────────┘" -ForegroundColor DarkGray
}

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  DEPLOYMENT SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($createdSubagents.Count -gt 0) {
    Write-Host "  ✅ Created via REST API:" -ForegroundColor Green
    foreach ($name in $createdSubagents) {
        Write-Host "     • $name" -ForegroundColor Green
    }
    Write-Host ""
}

if ($failedSubagents.Count -gt 0) {
    Write-Host "  📋 Manual portal creation needed ($($failedSubagents.Count) subagents):" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "     Paste files are in: $OutputDir" -ForegroundColor White
    Write-Host ""
    foreach ($entry in $failedSubagents) {
        Write-Host "     $($entry.Parsed.Tools.Count) tools │ $($entry.Name)" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "     Portal steps per subagent:" -ForegroundColor Gray
    Write-Host "       1. Subagent Builder → Create → Subagent" -ForegroundColor Gray
    Write-Host "       2. Name: paste from portal-paste.md" -ForegroundColor Gray
    Write-Host "       3. Instructions: paste system_prompt block" -ForegroundColor Gray
    Write-Host "       4. Handoff Description: paste handoff block" -ForegroundColor Gray
    Write-Host "       5. Built-in Tools: check the listed tools" -ForegroundColor Gray
    Write-Host "       6. Save" -ForegroundColor Gray
}

Write-Host ""
Write-Host "  📂 Output files:" -ForegroundColor White
Get-ChildItem $OutputDir | ForEach-Object {
    Write-Host "     • $($_.Name)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
