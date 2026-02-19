[CmdletBinding()]
param(
  [Parameter(Mandatory = $false)]
  [string] $KeyVaultName = $env:KEYVAULT_NAME,

  [Parameter(Mandatory = $false)]
  [string] $EndpointSecretName = 'artifactSigningEndpoint',

  [Parameter(Mandatory = $false)]
  [string] $AccountNameSecretName = 'artifactSigningAccountName',

  [Parameter(Mandatory = $false)]
  [string] $CertNameSecretName = 'artifactSigningCertificateProfileName',

  [Parameter(Mandatory = $false)]
  [string] $IdentityValidationIdSecretName = 'artifactSigningIdentityValidationId'
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  throw "Missing required command 'az'. Install Azure CLI and ensure it is on PATH."
}

if ([string]::IsNullOrWhiteSpace($KeyVaultName)) {
  throw "Missing KEYVAULT_NAME. Set it as an environment variable or pass -KeyVaultName."
}

function Get-KvSecret([string]$name) {
  $value = az keyvault secret show --vault-name $KeyVaultName --name $name --query value -o tsv
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to read Key Vault secret '$name' from vault '$KeyVaultName'."
  }
  if ($null -eq $value) { return '' }
  return "$value".Trim()
}

$endpoint = Get-KvSecret $EndpointSecretName
$account  = Get-KvSecret $AccountNameSecretName
$certName  = Get-KvSecret $CertNameSecretName
$idvId    = Get-KvSecret $IdentityValidationIdSecretName

if ([string]::IsNullOrWhiteSpace($endpoint)) { throw "Key Vault secret $EndpointSecretName is empty." }
if ([string]::IsNullOrWhiteSpace($account))  { throw "Key Vault secret $AccountNameSecretName is empty." }
if ([string]::IsNullOrWhiteSpace($certName))  { throw "Key Vault secret $CertNameSecretName is empty." }

# Mask in GitHub Actions logs when possible.
if ($env:GITHUB_ACTIONS -eq 'true') {
  Write-Host "::add-mask::$endpoint"
  Write-Host "::add-mask::$account"
  Write-Host "::add-mask::$certName"
  if (-not [string]::IsNullOrWhiteSpace($idvId)) { Write-Host "::add-mask::$idvId" }
}

$vars = @{
  ARTIFACT_SIGNING_ENDPOINT               = $endpoint
  ARTIFACT_SIGNING_ACCOUNT_NAME           = $account
  ARTIFACT_SIGNING_CERT_PROFILE_NAME      = $certName
  ARTIFACT_SIGNING_IDENTITY_VALIDATION_ID = $idvId
}

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_ENV)) {
  foreach ($k in $vars.Keys) {
    "$k=$($vars[$k])" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
  }

  Write-Host "Loaded signing configuration from Key Vault '$KeyVaultName' into GITHUB_ENV."
} else {
  # For local usage: write NAME=value lines.
  foreach ($k in $vars.Keys) {
    Write-Output "$k=$($vars[$k])"
  }
}
