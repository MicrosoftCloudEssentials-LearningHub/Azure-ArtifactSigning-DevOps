[CmdletBinding()]
param(
  [Parameter(Mandatory = $false)]
  [string] $TerraformTfvarsPath = (Join-Path $PSScriptRoot '..' 'terraform-infrastructure' 'terraform.tfvars'),

  [Parameter(Mandatory = $false)]
  [string] $Owner,

  [Parameter(Mandatory = $false)]
  [string] $Repo,

  [Parameter(Mandatory = $false)]
  [string] $Ref
)

$ErrorActionPreference = 'Stop'

function Get-OriginUrl {
  try {
    $url = (git config --get remote.origin.url) 2>$null
    if (-not [string]::IsNullOrWhiteSpace($url)) { return $url.Trim() }

    $url = (git remote get-url origin) 2>$null
    if (-not [string]::IsNullOrWhiteSpace($url)) { return $url.Trim() }
  } catch {
    # ignore
  }
  return $null
}

function Parse-GithubOwnerRepo([string]$url) {
  if ([string]::IsNullOrWhiteSpace($url)) { return $null }

  # Supported:
  # - git@github.com:owner/repo.git
  # - ssh://git@github.com/owner/repo.git
  # - https://github.com/owner/repo.git
  # - https://github.com/owner/repo
  $patterns = @(
    '^git@github\.com:(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$',
    '^ssh://git@github\.com/(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$',
    '^https://github\.com/(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$'
  )

  foreach ($pattern in $patterns) {
    $m = [regex]::Match($url.Trim(), $pattern)
    if ($m.Success) {
      return @{
        owner = $m.Groups['owner'].Value
        repo  = $m.Groups['repo'].Value
      }
    }
  }

  return $null
}

function Set-TfvarsValue([string]$content, [string]$name, [string]$valueLiteral) {
  # Replaces a line like: name = ...
  $escaped = [regex]::Escape($name)
  $pattern = "(?m)^\s*${escaped}\s*=\s*.*$"
  $replacement = "${name} = ${valueLiteral}"

  if ([regex]::IsMatch($content, $pattern)) {
    return [regex]::Replace($content, $pattern, $replacement)
  }

  # If variable isn't present, append it.
  return ($content.TrimEnd() + "`r`n${replacement}`r`n")
}

if (-not (Test-Path -LiteralPath $TerraformTfvarsPath)) {
  throw "tfvars not found: $TerraformTfvarsPath"
}

$originUrl = Get-OriginUrl
if (-not [string]::IsNullOrWhiteSpace($originUrl)) {
  Write-Host "Detected origin URL: $originUrl"

  if (-not $Owner -or -not $Repo) {
    $parsed = Parse-GithubOwnerRepo -url $originUrl
    if ($parsed) {
      if (-not $Owner) { $Owner = $parsed.owner }
      if (-not $Repo) { $Repo = $parsed.repo }
    }
  }
} else {
  Write-Host "No git origin remote detected (this may be a zip download)."
}

if (-not $Owner) {
  $Owner = Read-Host "GitHub owner/org"
}
if (-not $Repo) {
  $Repo = Read-Host "GitHub repo name"
}

if (-not $Ref) {
  $branch = $null
  try { $branch = (git symbolic-ref --short HEAD) 2>$null } catch { }
  if ([string]::IsNullOrWhiteSpace($branch)) { $branch = 'main' }

  $defaultRef = "refs/heads/$branch"
  $inputRef = Read-Host "GitHub ref for OIDC subject (default: $defaultRef)"
  $Ref = if ([string]::IsNullOrWhiteSpace($inputRef)) { $defaultRef } else { $inputRef.Trim() }
}

if ($Ref -notmatch '^refs/heads/[^\s]+$') {
  throw "github_ref must look like refs/heads/<branch>. Got: $Ref"
}

Write-Host "\nUpdating tfvars: $TerraformTfvarsPath"
Write-Host " - github_enabled = true"
Write-Host " - github_owner   = $Owner"
Write-Host " - github_repo    = $Repo"
Write-Host " - github_ref     = $Ref\n"

$content = Get-Content -LiteralPath $TerraformTfvarsPath -Raw
$content = Set-TfvarsValue -content $content -name 'github_enabled' -valueLiteral 'true'
$content = Set-TfvarsValue -content $content -name 'github_owner' -valueLiteral ('"' + $Owner + '"')
$content = Set-TfvarsValue -content $content -name 'github_repo' -valueLiteral ('"' + $Repo + '"')
$content = Set-TfvarsValue -content $content -name 'github_ref' -valueLiteral ('"' + $Ref + '"')

Set-Content -LiteralPath $TerraformTfvarsPath -Value $content -Encoding utf8

Write-Host "Done. Next:" 
Write-Host "  cd terraform-infrastructure"
Write-Host "  terraform apply -auto-approve"
