param(
  [Parameter(Mandatory = $false)]
  [string] $RepoRoot = (Join-Path $PSScriptRoot '..'),

  [Parameter(Mandatory = $false)]
  [string] $TerraformDir = (Join-Path $PSScriptRoot '..' 'terraform-infrastructure'),

  [Parameter(Mandatory = $false)]
  [string] $TfvarsPath = (Join-Path $PSScriptRoot '..' 'terraform-infrastructure' 'terraform.tfvars'),

  [Parameter(Mandatory = $false)]
  [string] $Owner,

  [Parameter(Mandatory = $false)]
  [string] $Repo,

  [Parameter(Mandatory = $false)]
  [string] $Ref,

  # By default, this script runs a single terraform apply.
  # Identity validation + certificate profile creation are portal-only steps.
  [ValidateSet('interactive', 'noninteractive')]
  [string] $TerraformApplyMode = 'noninteractive',

  [bool] $SkipGhSecrets = $false,

  [bool] $RequireApproval = $false
)

$ErrorActionPreference = 'Stop'

function Get-AzContext {
  $sub = (az account show --query id -o tsv) 2>$null
  $tenant = (az account show --query tenantId -o tsv) 2>$null
  if ([string]::IsNullOrWhiteSpace($sub) -or [string]::IsNullOrWhiteSpace($tenant)) {
    throw "Azure CLI not logged in. Run: az login"
  }
  return @{ subscriptionId = $sub.Trim(); tenantId = $tenant.Trim() }
}

function Get-TerraformOutput([string]$name) {
  $v = (terraform -chdir=$TerraformDir output -raw $name) 2>$null
  if ($LASTEXITCODE -ne 0) { return $null }
  if ($null -eq $v) { return $null }
  return "$v".Trim()
}

function Get-IdentityValidationIdFromTfvars([string]$tfvarsRaw) {
  # Supports either: identity_validation_id = null OR identity_validation_id = "..."
  $m = [regex]::Match($tfvarsRaw, '(?m)^\s*identity_validation_id\s*=\s*(?<v>.+?)\s*$')
  if (-not $m.Success) { return $null }

  $v = $m.Groups['v'].Value.Trim()
  if ($v -match '^(?i)null$') { return $null }

  $quoted = [regex]::Match($v, '^"(?<q>.*)"$')
  if ($quoted.Success) { return $quoted.Groups['q'].Value.Trim() }

  return $v.Trim()
}

function Set-GhSecret([string]$repoFullName, [string]$name, [string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "Cannot set GitHub secret '$name' because value is empty."
  }

  # Note: these values (tenant/subscription/client id) are identifiers, but we still store them as secrets
  # because the workflow expects them under secrets.*.
  gh secret set $name -R $repoFullName -b $value | Out-Host
}

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
  throw "Missing required command 'terraform'. Install Terraform and ensure it is on PATH."
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  throw "Missing required command 'az'. Install Azure CLI and ensure it is on PATH."
}

if (-not (Test-Path -LiteralPath $RepoRoot)) { throw "RepoRoot not found: $RepoRoot" }
if (-not (Test-Path -LiteralPath $TerraformDir)) { throw "TerraformDir not found: $TerraformDir" }
if (-not (Test-Path -LiteralPath $TfvarsPath)) { throw "TfvarsPath not found: $TfvarsPath" }

Set-Location -LiteralPath $RepoRoot

Write-Host "== Phase 1: Configure GitHub OIDC (tfvars) =="
$configureScript = Join-Path $RepoRoot 'scripts' 'configure-github-oidc.ps1'
if (-not (Test-Path -LiteralPath $configureScript)) {
  throw "Missing helper script: $configureScript"
}

$configureArgs = @('-TerraformTfvarsPath', $TfvarsPath)
if ($Owner) { $configureArgs += @('-Owner', $Owner) }
if ($Repo) { $configureArgs += @('-Repo', $Repo) }
if ($Ref) { $configureArgs += @('-Ref', $Ref) }

pwsh -NoProfile -ExecutionPolicy Bypass -File $configureScript @configureArgs | Out-Host

Write-Host "== Phase 2: Terraform apply (infra + identity + RBAC) =="
$applyScript = Join-Path $RepoRoot 'scripts' 'terraform-apply.ps1'
if (-not (Test-Path -LiteralPath $applyScript)) {
  throw "Missing script: $applyScript"
}

$autoApprove = -not $RequireApproval
if ($TerraformApplyMode -eq 'interactive') {
  pwsh -NoProfile -ExecutionPolicy Bypass -File $applyScript -TerraformDir $TerraformDir -TfvarsPath $TfvarsPath -AutoApprove $autoApprove -Interactive | Out-Host
} else {
  pwsh -NoProfile -ExecutionPolicy Bypass -File $applyScript -TerraformDir $TerraformDir -TfvarsPath $TfvarsPath -AutoApprove $autoApprove | Out-Host
}

if ($SkipGhSecrets) {
  Write-Host "Skipping GitHub secrets configuration (--SkipGhSecrets)."
  exit 0
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw "Missing required command 'gh'. Install GitHub CLI ('gh') and authenticate with: gh auth login"
}

try {
  gh auth status | Out-Host
} catch {
  throw "GitHub CLI is not authenticated. Run: gh auth login"
}

Write-Host "== Phase 3: Configure GitHub Actions secrets via gh CLI =="

# Determine repo full name from tfvars (best source, since it's what OIDC subject is built from)
$tf = Get-Content -LiteralPath $TfvarsPath -Raw
$ownerMatch = [regex]::Match($tf, '(?m)^\s*github_owner\s*=\s*"(?<v>[^"]+)"\s*$')
$repoMatch  = [regex]::Match($tf, '(?m)^\s*github_repo\s*=\s*"(?<v>[^"]+)"\s*$')
if (-not $ownerMatch.Success -or -not $repoMatch.Success) {
  throw "Unable to read github_owner/github_repo from $TfvarsPath"
}
$repoFull = "$($ownerMatch.Groups['v'].Value)/$($repoMatch.Groups['v'].Value)"
Write-Host "Target GitHub repo: $repoFull"

# Azure identifiers from az
$azCtx = Get-AzContext

# Terraform outputs
$clientId = Get-TerraformOutput 'github_app_client_id'
$kvName   = Get-TerraformOutput 'keyvault_name'
$rgName   = Get-TerraformOutput 'resource_group_name'

if ([string]::IsNullOrWhiteSpace($clientId)) {
  throw "Terraform output github_app_client_id is empty. Ensure github_enabled=true and re-apply."
}

Set-GhSecret -repoFullName $repoFull -name 'AZURE_CLIENT_ID' -value $clientId
Set-GhSecret -repoFullName $repoFull -name 'AZURE_TENANT_ID' -value $azCtx.tenantId
Set-GhSecret -repoFullName $repoFull -name 'AZURE_SUBSCRIPTION_ID' -value $azCtx.subscriptionId
Set-GhSecret -repoFullName $repoFull -name 'KEYVAULT_NAME' -value $kvName
Set-GhSecret -repoFullName $repoFull -name 'ARTIFACT_SIGNING_RESOURCE_GROUP' -value $rgName

$tfAfter = Get-Content -LiteralPath $TfvarsPath -Raw
$idvAfter = Get-IdentityValidationIdFromTfvars -tfvarsRaw $tfAfter

Write-Host "\nBootstrap complete."

if ([string]::IsNullOrWhiteSpace($idvAfter)) {
  Write-Host "Remaining manual steps (service requirement):" -ForegroundColor Yellow
  Write-Host " - In Azure Portal, create an Identity validation record" -ForegroundColor Yellow
  Write-Host " - In Azure Portal, create the certificate profile (name should match certificate_profile_name)" -ForegroundColor Yellow
  Write-Host " "
  Write-Host "Optional (Terraform-managed certificate profile):" -ForegroundColor Yellow
  Write-Host " - After completing Identity validation, copy the Identity validation Id (GUID)" -ForegroundColor Yellow
  Write-Host " - Then run the guided flow to persist it and create the profile via Terraform:" -ForegroundColor Yellow
  Write-Host "   pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\terraform-apply.ps1 -Interactive" -ForegroundColor Yellow
} else {
  Write-Host "Identity validation Id is set in tfvars. Next: commit/push to main and run the GitHub Actions workflow to test signing." 
}
