locals {
  endpoint_by_location = {
    brazilsouth      = "https://brs.codesigning.azure.net"
    centralus        = "https://cus.codesigning.azure.net"
    eastus           = "https://eus.codesigning.azure.net"
    japaneast        = "https://jpe.codesigning.azure.net"
    koreacentral     = "https://krc.codesigning.azure.net"
    northcentralus   = "https://ncus.codesigning.azure.net"
    northeurope      = "https://neu.codesigning.azure.net"
    polandcentral    = "https://plc.codesigning.azure.net"
    southcentralus   = "https://scus.codesigning.azure.net"
    switzerlandnorth = "https://swn.codesigning.azure.net"
    westcentralus    = "https://wcus.codesigning.azure.net"
    westeurope       = "https://weu.codesigning.azure.net"
    westus           = "https://wus.codesigning.azure.net"
    westus2          = "https://wus2.codesigning.azure.net"
    westus3          = "https://wus3.codesigning.azure.net"
  }

  artifact_signing_endpoint = try(local.endpoint_by_location[lower(replace(var.location, " ", ""))], null)

  identity_validation_id_trimmed = trimspace(var.identity_validation_id == null ? "" : var.identity_validation_id)

  keyvault_name_input = var.keyvault_name != null ? trimspace(var.keyvault_name) : ""

  github_owner_input_trimmed = trimspace(var.github_owner == null ? "" : var.github_owner)
  github_repo_input_trimmed  = trimspace(var.github_repo == null ? "" : var.github_repo)
  github_ref_input_trimmed   = trimspace(var.github_ref)

  github_owner_detected = try(trimspace(data.external.github_oidc[0].result.owner), "")
  github_repo_detected  = try(trimspace(data.external.github_oidc[0].result.repo), "")
  github_ref_detected   = try(trimspace(data.external.github_oidc[0].result.ref), "")

  github_owner_effective = var.github_enabled ? (
    (local.github_owner_input_trimmed != "" && !strcontains(upper(local.github_owner_input_trimmed), "REPLACE_ME")) ? local.github_owner_input_trimmed : local.github_owner_detected
  ) : null

  github_repo_effective = var.github_enabled ? (
    (local.github_repo_input_trimmed != "" && !strcontains(upper(local.github_repo_input_trimmed), "REPLACE_ME")) ? local.github_repo_input_trimmed : local.github_repo_detected
  ) : null

  github_ref_effective = var.github_enabled ? (
    local.github_ref_input_trimmed != "" ? local.github_ref_input_trimmed : (
      local.github_ref_detected != "" ? local.github_ref_detected : "refs/heads/main"
    )
  ) : null

  github_repository  = (local.github_owner_effective != null && local.github_owner_effective != "" && local.github_repo_effective != null && local.github_repo_effective != "") ? "${local.github_owner_effective}/${local.github_repo_effective}" : null
  github_fic_subject = local.github_repository != null ? "repo:${local.github_repository}:ref:${local.github_ref_effective}" : null

  github_sp_object_id_effective = var.github_enabled ? try(azuread_service_principal.github_sp[0].object_id, null) : null
}

data "external" "github_oidc" {
  count = var.github_enabled && var.github_autodetect ? 1 : 0

  program = [
    "pwsh",
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    "${path.module}/detect-github-oidc.ps1"
  ]

  query = {
    enabled = "true"
  }
}

data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azapi_resource" "code_signing_account" {
  type      = "Microsoft.CodeSigning/codeSigningAccounts@2025-10-13"
  name      = var.code_signing_account_name
  location  = azurerm_resource_group.rg.location
  parent_id = azurerm_resource_group.rg.id
  tags      = var.tags

  body = {
    properties = {
      sku = {
        name = var.code_signing_sku
      }
    }
  }
}

resource "azurerm_role_assignment" "current_identity_verifier" {
  count = var.assign_identity_verifier_role_to_current ? 1 : 0

  scope                = azapi_resource.code_signing_account.id
  role_definition_name = "Artifact Signing Identity Verifier"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azapi_resource" "certificate_profile" {
  count     = local.identity_validation_id_trimmed != "" ? 1 : 0
  type      = "Microsoft.CodeSigning/codeSigningAccounts/certificateProfiles@2025-10-13"
  name      = var.certificate_profile_name
  parent_id = azapi_resource.code_signing_account.id

  body = {
    properties = {
      identityValidationId  = local.identity_validation_id_trimmed
      profileType           = var.certificate_profile_type
      includeStreetAddress  = var.certificate_profile_include_street_address
      includePostalCode     = var.certificate_profile_include_postal_code
    }
  }
}

resource "azuread_application" "github_app" {
  count        = var.github_enabled ? 1 : 0
  display_name = var.github_app_display_name
}

resource "azuread_service_principal" "github_sp" {
  count     = var.github_enabled ? 1 : 0
  client_id = azuread_application.github_app[0].client_id
}

resource "azuread_application_federated_identity_credential" "github_fic" {
  count          = var.github_enabled ? 1 : 0
  application_id = azuread_application.github_app[0].id
  display_name   = "github-actions"
  description    = "GitHub Actions OIDC federated credential"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = local.github_fic_subject

  depends_on = [azuread_service_principal.github_sp]

  lifecycle {
    precondition {
      condition = (
        var.github_enabled == false || (
          local.github_owner_effective != null && local.github_owner_effective != "" &&
          local.github_repo_effective != null && local.github_repo_effective != "" &&
          local.github_ref_effective != null && can(regex("^refs/heads/[^\\s]+$", local.github_ref_effective))
        )
      )

      error_message = "github_enabled=true but GitHub repo/ref could not be determined. Either set github_owner/github_repo/github_ref explicitly, or set github_autodetect=true and run Terraform from a git clone with origin pointing to https://github.com/<owner>/<repo>.git (or SSH equivalent)."
    }
  }
}

resource "azurerm_role_assignment" "github_account_signer" {
  count = var.assign_signer_role_to_github_sp_at_account_scope && var.github_enabled ? 1 : 0

  scope                = azapi_resource.code_signing_account.id
  role_definition_name = "Artifact Signing Certificate Profile Signer"
  principal_id         = local.github_sp_object_id_effective
}

resource "azurerm_role_assignment" "github_profile_signer" {
  count = var.assign_signer_role_to_github_sp && var.github_enabled && length(azapi_resource.certificate_profile) > 0 ? 1 : 0

  scope                = azapi_resource.certificate_profile[0].id
  role_definition_name = "Artifact Signing Certificate Profile Signer"
  principal_id         = local.github_sp_object_id_effective
}

resource "azurerm_role_assignment" "github_rg_contributor" {
  count = var.assign_contributor_role_to_github_sp && var.github_enabled ? 1 : 0

  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Contributor"
  principal_id         = local.github_sp_object_id_effective
}

resource "random_string" "kv_suffix" {
  count   = var.keyvault_enabled && local.keyvault_name_input == "" ? 1 : 0
  length  = 20
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  keyvault_name_effective = var.keyvault_enabled ? (local.keyvault_name_input != "" ? local.keyvault_name_input : "kv${random_string.kv_suffix[0].result}") : null
}

resource "azurerm_key_vault" "kv" {
  count               = var.keyvault_enabled ? 1 : 0
  name                = local.keyvault_name_effective
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = lower(var.keyvault_sku_name)

  # Prefer Azure RBAC for this demo.
  rbac_authorization_enabled      = true
  public_network_access_enabled   = true
  purge_protection_enabled        = false
  soft_delete_retention_days      = 7

  tags = var.tags
}

resource "azurerm_role_assignment" "kv_secrets_officer_current" {
  count                = var.keyvault_enabled && var.keyvault_populate_secrets ? 1 : 0
  scope                = azurerm_key_vault.kv[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "kv_crypto_user_current" {
  count                = var.keyvault_enabled && var.keyvault_grant_keys_access_to_current ? 1 : 0
  scope                = azurerm_key_vault.kv[0].id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "kv_certificates_user_current" {
  count                = var.keyvault_enabled && var.keyvault_grant_certificates_access_to_current ? 1 : 0
  scope                = azurerm_key_vault.kv[0].id
  role_definition_name = "Key Vault Certificates User"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "kv_administrator_current" {
  count                = var.keyvault_enabled && var.keyvault_grant_administrator_to_current ? 1 : 0
  scope                = azurerm_key_vault.kv[0].id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "kv_secrets_user_github" {
  count                = var.keyvault_enabled && var.github_enabled ? 1 : 0
  scope                = azurerm_key_vault.kv[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = local.github_sp_object_id_effective
}

resource "time_sleep" "kv_rbac_propagation" {
  count           = var.keyvault_enabled && var.rbac_propagation_wait_duration != "0s" ? 1 : 0
  create_duration = var.rbac_propagation_wait_duration

  depends_on = [
    azurerm_role_assignment.kv_secrets_officer_current,
    azurerm_role_assignment.kv_secrets_user_github,
    azurerm_role_assignment.kv_administrator_current,
  ]
}

resource "azurerm_key_vault_secret" "artifact_signing_endpoint" {
  count        = var.keyvault_enabled && var.keyvault_populate_secrets ? 1 : 0
  key_vault_id = azurerm_key_vault.kv[0].id
  name         = "artifactSigningEndpoint"
  value        = local.artifact_signing_endpoint != null ? local.artifact_signing_endpoint : " "

  depends_on = [
    azurerm_role_assignment.kv_secrets_officer_current,
    time_sleep.kv_rbac_propagation,
  ]
}

resource "azurerm_key_vault_secret" "artifact_signing_account_name" {
  count        = var.keyvault_enabled && var.keyvault_populate_secrets ? 1 : 0
  key_vault_id = azurerm_key_vault.kv[0].id
  name         = "artifactSigningAccountName"
  value        = azapi_resource.code_signing_account.name

  depends_on = [
    azurerm_role_assignment.kv_secrets_officer_current,
    time_sleep.kv_rbac_propagation,
  ]
}

resource "azurerm_key_vault_secret" "artifact_signing_certificate_profile_name" {
  count        = var.keyvault_enabled && var.keyvault_populate_secrets ? 1 : 0
  key_vault_id = azurerm_key_vault.kv[0].id
  name         = "artifactSigningCertificateProfileName"
  value        = var.certificate_profile_name

  depends_on = [
    azurerm_role_assignment.kv_secrets_officer_current,
    time_sleep.kv_rbac_propagation,
  ]
}

resource "azurerm_key_vault_secret" "artifact_signing_identity_validation_id" {
  count        = var.keyvault_enabled && var.keyvault_populate_secrets ? 1 : 0
  key_vault_id = azurerm_key_vault.kv[0].id
  name         = "artifactSigningIdentityValidationId"
  value        = local.identity_validation_id_trimmed != "" ? local.identity_validation_id_trimmed : " "

  depends_on = [
    azurerm_role_assignment.kv_secrets_officer_current,
    time_sleep.kv_rbac_propagation,
  ]
}

