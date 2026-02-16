<#
.SYNOPSIS
    Deploys SRE Agent demo workload resources to Azure.

.DESCRIPTION
    This script deploys intentionally misconfigured Azure resources that the
    SRE Optimization Agent can analyze for cost and performance optimization findings.

    Resources deployed:
    - VNet + Subnet + NSG
    - 3 VMs (oversized old-gen, Spot candidate, no-zone)
    - 2 orphaned managed disks
    - 2 storage accounts (Hot without lifecycle, Cool with lifecycle)

.PARAMETER Location
    Azure region. Default: swedencentral

.PARAMETER SubscriptionId
    Target subscription ID. If not provided, uses current context.

.PARAMETER SshPublicKeyPath
    Path to SSH public key file. Default: ~/.ssh/id_rsa.pub

.EXAMPLE
    .\deploy-demo.ps1
    .\deploy-demo.ps1 -SubscriptionId "0a659fdc-7842-48ca-a297-09d166711ef7"
    .\deploy-demo.ps1 -SshPublicKeyPath "C:\Users\me\.ssh\mykey.pub"
#>

param(
    [string]$Location = "swedencentral",
    [string]$SubscriptionId = "",
    [string]$SshPublicKeyPath = "$HOME\.ssh\id_rsa.pub",
    [string]$ResourceGroupName = "rg-sre-demo-workloads",
    [string]$NameSuffix = "sredemo"
)

$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " SRE Agent Demo Environment Deployment" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# --------------------------------------------------
# Pre-flight checks
# --------------------------------------------------

# Check Azure CLI
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI (az) is not installed. Install from https://aka.ms/installazurecli"
    exit 1
}

# Check login
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Not logged in. Running 'az login'..." -ForegroundColor Yellow
    az login
    $account = az account show | ConvertFrom-Json
}

# Set subscription
if ($SubscriptionId) {
    Write-Host "Setting subscription to: $SubscriptionId" -ForegroundColor Yellow
    az account set --subscription $SubscriptionId
    $account = az account show | ConvertFrom-Json
}

Write-Host "Subscription: $($account.name) ($($account.id))" -ForegroundColor Green
Write-Host "Location:     $Location" -ForegroundColor Green
Write-Host ""

# --------------------------------------------------
# SSH Key handling
# --------------------------------------------------

if (-not (Test-Path $SshPublicKeyPath)) {
    Write-Host "SSH public key not found at: $SshPublicKeyPath" -ForegroundColor Yellow
    Write-Host "Generating new SSH key pair..." -ForegroundColor Yellow
    $sshDir = Split-Path $SshPublicKeyPath -Parent
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }
    $privateKeyPath = $SshPublicKeyPath -replace '\.pub$', ''
    ssh-keygen -t rsa -b 4096 -f $privateKeyPath -N '""' -q
    Write-Host "SSH key pair generated at: $privateKeyPath" -ForegroundColor Green
}

$sshPublicKey = Get-Content $SshPublicKeyPath -Raw
$sshPublicKey = $sshPublicKey.Trim()
Write-Host "SSH public key loaded from: $SshPublicKeyPath" -ForegroundColor Green
Write-Host ""

# --------------------------------------------------
# Deploy
# --------------------------------------------------

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$templateFile = Join-Path $scriptDir "main.bicep"
$deploymentName = "sre-demo-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

Write-Host "Starting deployment: $deploymentName" -ForegroundColor Cyan
Write-Host "Template:  $templateFile" -ForegroundColor Gray
Write-Host ""

$startTime = Get-Date

az deployment sub create `
    --name $deploymentName `
    --location $Location `
    --template-file $templateFile `
    --parameters `
        location=$Location `
        resourceGroupName=$ResourceGroupName `
        adminUsername="azureuser" `
        sshPublicKey=$sshPublicKey `
        nameSuffix=$NameSuffix `
    --verbose

if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed! Check the Azure portal for details."
    exit 1
}

$duration = (Get-Date) - $startTime

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Deployment Successful!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "Duration:       $($duration.ToString('mm\:ss'))" -ForegroundColor Green
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Green
Write-Host "Location:       $Location" -ForegroundColor Green
Write-Host ""
Write-Host "Resources deployed for SRE Agent analysis:" -ForegroundColor Cyan
Write-Host "  VM1: vm-oversized-v3         (D8s_v3, oversized + old gen)" -ForegroundColor White
Write-Host "  VM2: vm-devtest-nospotv5     (D4s_v5, Spot candidate)" -ForegroundColor White
Write-Host "  VM3: vm-nozone-staging       (D2s_v3, no AZ + old gen)" -ForegroundColor White
Write-Host "  Disk: disk-orphan-premium-512 (Premium, unattached)" -ForegroundColor White
Write-Host "  Disk: disk-orphan-std-1024    (StandardSSD, unattached)" -ForegroundColor White
Write-Host "  Storage: st${NameSuffix}hotnolc   (Hot, no lifecycle)" -ForegroundColor White
Write-Host "  Storage: st${NameSuffix}lifecycle  (Cool, with lifecycle)" -ForegroundColor White
Write-Host ""
Write-Host "Expected SRE Agent findings:" -ForegroundColor Yellow
Write-Host "  1. Rightsizing:    vm-oversized-v3 (D8s_v3 → D2s_v5)" -ForegroundColor White
Write-Host "  2. Gen upgrade:   vm-oversized-v3, vm-nozone-staging (v3 → v5)" -ForegroundColor White
Write-Host "  3. Spot VM:       vm-devtest-nospotv5 (dev/test → Spot)" -ForegroundColor White
Write-Host "  4. HA gap:        vm-nozone-staging (no availability zone)" -ForegroundColor White
Write-Host "  5. Orphan disks:  2 unattached disks → cleanup" -ForegroundColor White
Write-Host "  6. Disk tier:     vm1 Premium data disk → downgrade" -ForegroundColor White
Write-Host "  7. Lifecycle:     sthotnolc → add lifecycle policy" -ForegroundColor White
Write-Host "  8. Network:       sthotnolc → restrict network access" -ForegroundColor White
Write-Host ""
Write-Host "Next: Point the SRE Agent at '$ResourceGroupName' to generate findings." -ForegroundColor Cyan
