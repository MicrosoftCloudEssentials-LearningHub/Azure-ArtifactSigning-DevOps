[CmdletBinding()]
param(
  [Parameter(Mandatory = $false)]
  [string] $Owner,

  [Parameter(Mandatory = $false)]
  [string] $Repo,

  [Parameter(Mandatory = $false)]
  [string] $Ref,

  [Parameter(Mandatory = $false)]
  [bool] $EnableGitHub = $true
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

# 1) Prefer GitHub Actions env vars when running in CI
if ((-not $Owner -or -not $Repo) -and -not [string]::IsNullOrWhiteSpace($env:GITHUB_REPOSITORY)) {
  $parts = $env:GITHUB_REPOSITORY.Split('/')
  if ($parts.Count -eq 2) {
    if (-not $Owner) { $Owner = $parts[0] }
    if (-not $Repo) { $Repo = $parts[1] }
  }
}

if (-not $Ref -and -not [string]::IsNullOrWhiteSpace($env:GITHUB_REF)) {
  $Ref = $env:GITHUB_REF.Trim()
}

# 2) Next, try local git remote
if (-not $Owner -or -not $Repo) {
  $originUrl = Get-OriginUrl
  if (-not [string]::IsNullOrWhiteSpace($originUrl)) {
    $parsed = Parse-GithubOwnerRepo -url $originUrl
    if ($parsed) {
      if (-not $Owner) { $Owner = $parsed.owner }
      if (-not $Repo) { $Repo = $parsed.repo }
    }
  }
}

# 3) Optional: use GitHub CLI if available (still not required)
if (-not $Owner -or -not $Repo) {
  if (Get-Command gh -ErrorAction SilentlyContinue) {
    try {
      $json = gh repo view --json owner,name 2>$null
      if (-not [string]::IsNullOrWhiteSpace($json)) {
        $obj = $json | ConvertFrom-Json
        if (-not $Owner -and $obj.owner -and $obj.owner.login) { $Owner = $obj.owner.login }
        if (-not $Repo -and $obj.name) { $Repo = $obj.name }
      }
    } catch {
      # ignore
    }
  }
}

# 4) Fallback: prompt
if (-not $Owner) { $Owner = Read-Host 'GitHub owner/org' }
if (-not $Repo)  { $Repo  = Read-Host 'GitHub repo name' }

if (-not $Ref) {
  $branch = $null
  try { $branch = (git symbolic-ref --short HEAD) 2>$null } catch { }
  if ([string]::IsNullOrWhiteSpace($branch)) { $branch = 'main' }
  $Ref = "refs/heads/$branch"
}

$Owner = $Owner.Trim()
$Repo  = $Repo.Trim()
$Ref   = $Ref.Trim()

if ($Ref -notmatch '^refs/heads/[^\s]+$') {
  throw "github_ref must look like refs/heads/<branch>. Got: $Ref"
}

# Set Terraform environment variables for the current PowerShell process
$env:TF_VAR_github_enabled = if ($EnableGitHub) { 'true' } else { 'false' }
$env:TF_VAR_github_owner   = $Owner
$env:TF_VAR_github_repo    = $Repo
$env:TF_VAR_github_ref     = $Ref

Write-Host "Set TF_VAR_* for GitHub OIDC:"
Write-Host " - TF_VAR_github_enabled=$($env:TF_VAR_github_enabled)"
Write-Host " - TF_VAR_github_owner=$($env:TF_VAR_github_owner)"
Write-Host " - TF_VAR_github_repo=$($env:TF_VAR_github_repo)"
Write-Host " - TF_VAR_github_ref=$($env:TF_VAR_github_ref)"

Write-Host "\nNOTE: These env vars only apply to the current PowerShell session/process."
Write-Host "Use dot-sourcing to keep them in your current session:"
Write-Host "  . .\\scripts\\set-tf-vars-from-github.ps1"
