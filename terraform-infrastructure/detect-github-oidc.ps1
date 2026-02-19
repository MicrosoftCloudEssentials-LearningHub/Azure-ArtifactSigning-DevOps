$ErrorActionPreference = 'Stop'

# Terraform external data source sends JSON on stdin; we don't need it here.
try {
  $null = [Console]::In.ReadToEnd()
} catch {
  # ignore
}

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

$owner = ''
$repo = ''
$ref = ''

# Prefer GitHub Actions env vars if present.
if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_REPOSITORY)) {
  $parts = $env:GITHUB_REPOSITORY.Split('/')
  if ($parts.Count -eq 2) {
    $owner = $parts[0]
    $repo = $parts[1]
  }
}

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_REF)) {
  $ref = $env:GITHUB_REF.Trim()
}

# Otherwise, use local git.
if ([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($repo)) {
  $originUrl = Get-OriginUrl
  $parsed = Parse-GithubOwnerRepo -url $originUrl
  if ($parsed) {
    $owner = $parsed.owner
    $repo = $parsed.repo
  }
}

if ([string]::IsNullOrWhiteSpace($ref)) {
  $branch = $null
  try { $branch = (git symbolic-ref --short HEAD) 2>$null } catch { }
  if ([string]::IsNullOrWhiteSpace($branch)) { $branch = 'main' }
  $ref = "refs/heads/$branch"
}

# Must output JSON object of string -> string.
@{
  owner = "$owner".Trim()
  repo  = "$repo".Trim()
  ref   = "$ref".Trim()
} | ConvertTo-Json -Compress
