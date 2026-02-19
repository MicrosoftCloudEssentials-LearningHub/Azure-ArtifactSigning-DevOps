[CmdletBinding()]
param(
  [Parameter(Mandatory = $false)]
  [string] $TerraformDir = (Join-Path $PSScriptRoot '..' 'terraform-infrastructure'),

  [Parameter(Mandatory = $false)]
  [string] $TfvarsPath = (Join-Path $PSScriptRoot '..' 'terraform-infrastructure' 'terraform.tfvars'),

  # If true, auto-detect github_owner/repo/ref (from git/remote) and persist them into terraform.tfvars
  # by invoking scripts/configure-github-oidc.ps1. This is the "persist in repo" + "dynamic discovery" path.
  [Parameter(Mandatory = $false)]
  [bool] $EnableGitHubOidc = $false,

  # If provided, this script will update identity_validation_id in terraform.tfvars and run apply.
  [Parameter(Mandatory = $false)]
  [string] $IdentityValidationId,

  # If set, runs a guided 2-phase setup:
  #  1) terraform apply (creates account + RBAC)
  #  2) pauses for portal-only Identity validation
  #  3) prompts for Identity validation Id, persists it into tfvars, then applies again
  [Parameter(Mandatory = $false)]
  [switch] $Interactive,

  [Parameter(Mandatory = $false)]
  [bool] $AutoApprove = $true
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
  throw "Missing required command 'terraform'. Install Terraform and ensure it is on PATH."
}

function Set-TfvarsValue([string]$content, [string]$name, [string]$valueLiteral) {
  $escaped = [regex]::Escape($name)
  $pattern = "(?m)^\s*${escaped}\s*=\s*.*$"
  $replacement = "${name} = ${valueLiteral}"

  if ([regex]::IsMatch($content, $pattern)) {
    return [regex]::Replace($content, $pattern, $replacement)
  }

  return ($content.TrimEnd() + "`r`n${replacement}`r`n")
}

function Get-TfvarsRaw([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { throw "tfvars not found: $path" }
  return Get-Content -LiteralPath $path -Raw
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

function Test-IsGuid([string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) { return $false }
  return ($value.Trim() -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
}

function Prompt-ForIdentityValidationId {
  while ($true) {
    $v = Read-Host "Paste the Identity validation Id (GUID) from the Azure portal (or press Enter to stop)"
    if ([string]::IsNullOrWhiteSpace($v)) { return $null }
    $v = $v.Trim()
    if (Test-IsGuid -value $v) { return $v }
    Write-Host "Identity validation Id must be a GUID. Got: $v" -ForegroundColor Yellow
  }
}

if (-not (Test-Path -LiteralPath $TerraformDir)) {
  throw "TerraformDir not found: $TerraformDir"
}
if (-not (Test-Path -LiteralPath $TfvarsPath)) {
  throw "TfvarsPath not found: $TfvarsPath"
}

if ($EnableGitHubOidc) {
  $configureScript = Join-Path $PSScriptRoot 'configure-github-oidc.ps1'
  if (-not (Test-Path -LiteralPath $configureScript)) {
    throw "Missing script: $configureScript"
  }

  Write-Host "Auto-configuring GitHub OIDC values in tfvars..."
  pwsh -NoProfile -ExecutionPolicy Bypass -File $configureScript -TerraformTfvarsPath $TfvarsPath | Out-Host
}

# If the user provided an IdentityValidationId, persist it in tfvars (so future applies remain stable).
if (-not [string]::IsNullOrWhiteSpace($IdentityValidationId)) {
  $IdentityValidationId = $IdentityValidationId.Trim()

  if (-not (Test-IsGuid -value $IdentityValidationId)) {
    throw "IdentityValidationId must be a GUID. Got: $IdentityValidationId"
  }

  Write-Host "Persisting identity_validation_id into: $TfvarsPath"
  $raw = Get-TfvarsRaw -path $TfvarsPath
  $raw = Set-TfvarsValue -content $raw -name 'identity_validation_id' -valueLiteral ('"' + $IdentityValidationId + '"')
  Set-Content -LiteralPath $TfvarsPath -Value $raw -Encoding utf8
}

Write-Host "Running terraform init + apply in: $TerraformDir"
terraform -chdir=$TerraformDir init | Out-Host
terraform -chdir=$TerraformDir validate | Out-Host

$applyArgs = @('apply')
if ($AutoApprove) { $applyArgs += '-auto-approve' }
terraform -chdir=$TerraformDir @applyArgs | Out-Host

# Friendly guidance: if identity_validation_id still isn't set, the only remaining action is portal validation.
$rawAfter = Get-TfvarsRaw -path $TfvarsPath
$currentIdv = Get-IdentityValidationIdFromTfvars -tfvarsRaw $rawAfter

if ([string]::IsNullOrWhiteSpace($currentIdv)) {
  Write-Host "\nNext steps (portal-only):" 
  Write-Host "- Create an Identity validation record on the Artifact Signing account." 
  Write-Host "- Create the certificate profile in the portal (use the same name as certificate_profile_name)." 
  Write-Host "\nOptional (Terraform-managed certificate profile):" 
  Write-Host "- After completing Identity validation, copy the Identity validation Id (GUID)." 

  if ($Interactive) {
    $id = Prompt-ForIdentityValidationId
    if ([string]::IsNullOrWhiteSpace($id)) {
      Write-Host "Stopping without updating identity_validation_id. Re-run with -Interactive or -IdentityValidationId <GUID> when ready." -ForegroundColor Yellow
      exit 0
    }

    Write-Host "Persisting identity_validation_id into: $TfvarsPath"
    $raw = Get-TfvarsRaw -path $TfvarsPath
    $raw = Set-TfvarsValue -content $raw -name 'identity_validation_id' -valueLiteral ('"' + $id + '"')
    Set-Content -LiteralPath $TfvarsPath -Value $raw -Encoding utf8

    Write-Host "Re-running terraform apply to create the certificate profile..."
    terraform -chdir=$TerraformDir @applyArgs | Out-Host
  } else {
    Write-Host "Then re-run this script with the Id, for example:" 
    Write-Host "  pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\terraform-apply.ps1 -IdentityValidationId <GUID>" 
  }
}
