$ErrorActionPreference = 'Stop'

$identityValidationId = if ($args.Count -ge 1) { "$($args[0])" } else { $null }
if ([string]::IsNullOrWhiteSpace($identityValidationId)) {
  $identityValidationId = Read-Host "Paste the Identity validation Id (GUID) from the Azure portal"
}
$identityValidationId = $identityValidationId.Trim()

if ($identityValidationId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
  throw "Identity validation Id must be a GUID. Got: $identityValidationId"
}

$applyScript = Join-Path $PSScriptRoot 'terraform-apply.ps1'
if (-not (Test-Path -LiteralPath $applyScript)) {
  throw "Missing script: $applyScript"
}

pwsh -NoProfile -ExecutionPolicy Bypass -File $applyScript -IdentityValidationId $identityValidationId | Out-Host

Write-Host "\nPhase 2 complete. Next: merge/push to main to trigger GitHub Actions signing."
