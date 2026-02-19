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

  ado_sp_client_id = (
    length(trimspace(var.ado_service_principal_client_id == null ? "" : var.ado_service_principal_client_id)) > 0
  ) ? trimspace(var.ado_service_principal_client_id == null ? "" : var.ado_service_principal_client_id) : try(azuread_application.ado_app[0].client_id, null)

  ado_wif_issuer_effective = (
    length(trimspace(var.ado_wif_issuer == null ? "" : var.ado_wif_issuer)) > 0
  ) ? trimspace(var.ado_wif_issuer == null ? "" : var.ado_wif_issuer) : try(azuredevops_serviceendpoint_azurerm.azurerm[0].workload_identity_federation_issuer, null)

  ado_wif_subject_effective = (
    length(trimspace(var.ado_wif_subject == null ? "" : var.ado_wif_subject)) > 0
  ) ? trimspace(var.ado_wif_subject == null ? "" : var.ado_wif_subject) : try(azuredevops_serviceendpoint_azurerm.azurerm[0].workload_identity_federation_subject, null)

  keyvault_name_input = var.keyvault_name != null ? trimspace(var.keyvault_name) : ""
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

resource "azapi_resource" "certificate_profile" {
  count     = var.identity_validation_id == null ? 0 : 1
  type      = "Microsoft.CodeSigning/codeSigningAccounts/certificateProfiles@2025-10-13"
  name      = var.certificate_profile_name
  parent_id = azapi_resource.code_signing_account.id

  body = {
    properties = {
      identityValidationId  = var.identity_validation_id
      profileType           = var.certificate_profile_type
      includeStreetAddress  = var.certificate_profile_include_street_address
      includePostalCode     = var.certificate_profile_include_postal_code
    }
  }
}

resource "azuread_application" "ado_app" {
  count        = var.ado_enabled && var.ado_create_app ? 1 : 0
  display_name = var.ado_app_display_name
}

resource "azuread_service_principal" "ado_sp" {
  count     = var.ado_enabled && var.ado_create_app ? 1 : 0
  client_id = azuread_application.ado_app[0].client_id
}

resource "azuread_application_federated_identity_credential" "ado_fic" {
  count          = var.ado_enabled && var.ado_create_app && var.ado_service_endpoint_authentication_scheme == "WorkloadIdentityFederation" ? 1 : 0
  application_id = azuread_application.ado_app[0].id
  display_name   = "ado-wif"
  description    = "Azure DevOps workload identity federation"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = local.ado_wif_issuer_effective
  subject        = local.ado_wif_subject_effective

  depends_on = [azuredevops_serviceendpoint_azurerm.azurerm]
}

resource "azurerm_role_assignment" "ado_account_signer" {
  count = var.assign_signer_role_to_ado_sp && var.ado_enabled && var.ado_create_app ? 1 : 0

  scope                = azapi_resource.code_signing_account.id
  role_definition_name = "Artifact Signing Certificate Profile Signer"
  principal_id         = azuread_service_principal.ado_sp[0].object_id
}

resource "azurerm_role_assignment" "ado_profile_signer" {
  count = var.assign_signer_role_to_ado_sp && var.ado_enabled && var.ado_create_app && length(azapi_resource.certificate_profile) > 0 ? 1 : 0

  scope                = azapi_resource.certificate_profile[0].id
  role_definition_name = "Artifact Signing Certificate Profile Signer"
  principal_id         = azuread_service_principal.ado_sp[0].object_id
}

resource "azurerm_role_assignment" "ado_rg_contributor" {
  count = var.assign_contributor_role_to_ado_sp && var.ado_enabled && var.ado_create_app ? 1 : 0

  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.ado_sp[0].object_id
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
  count                = var.keyvault_enabled ? 1 : 0
  scope                = azurerm_key_vault.kv[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "kv_secrets_user_ado" {
  count                = var.keyvault_enabled && var.ado_enabled && var.ado_create_app ? 1 : 0
  scope                = azurerm_key_vault.kv[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azuread_service_principal.ado_sp[0].object_id
}

resource "time_sleep" "kv_rbac_propagation" {
  count           = var.keyvault_enabled && var.rbac_propagation_wait_duration != "0s" ? 1 : 0
  create_duration = var.rbac_propagation_wait_duration

  depends_on = [
    azurerm_role_assignment.kv_secrets_officer_current,
    azurerm_role_assignment.kv_secrets_user_ado,
  ]
}

resource "azurerm_key_vault_secret" "artifact_signing_endpoint" {
  count        = var.keyvault_enabled ? 1 : 0
  key_vault_id = azurerm_key_vault.kv[0].id
  name         = "artifactSigningEndpoint"
  value        = local.artifact_signing_endpoint != null ? local.artifact_signing_endpoint : " "

  depends_on = [
    azurerm_role_assignment.kv_secrets_officer_current,
    time_sleep.kv_rbac_propagation,
  ]
}

resource "azurerm_key_vault_secret" "artifact_signing_account_name" {
  count        = var.keyvault_enabled ? 1 : 0
  key_vault_id = azurerm_key_vault.kv[0].id
  name         = "artifactSigningAccountName"
  value        = azapi_resource.code_signing_account.name

  depends_on = [
    azurerm_role_assignment.kv_secrets_officer_current,
    time_sleep.kv_rbac_propagation,
  ]
}

resource "azurerm_key_vault_secret" "artifact_signing_certificate_profile_name" {
  count        = var.keyvault_enabled ? 1 : 0
  key_vault_id = azurerm_key_vault.kv[0].id
  name         = "artifactSigningCertificateProfileName"
  value        = var.certificate_profile_name

  depends_on = [
    azurerm_role_assignment.kv_secrets_officer_current,
    time_sleep.kv_rbac_propagation,
  ]
}

resource "azurerm_key_vault_secret" "artifact_signing_identity_validation_id" {
  count        = var.keyvault_enabled ? 1 : 0
  key_vault_id = azurerm_key_vault.kv[0].id
  name         = "artifactSigningIdentityValidationId"
  value        = local.identity_validation_id_trimmed != "" ? local.identity_validation_id_trimmed : " "

  depends_on = [
    azurerm_role_assignment.kv_secrets_officer_current,
    time_sleep.kv_rbac_propagation,
  ]
}

resource "time_sleep" "rbac_propagation" {
  count           = length(azurerm_role_assignment.ado_profile_signer) > 0 && var.rbac_propagation_wait_duration != "0s" ? 1 : 0
  create_duration = var.rbac_propagation_wait_duration

  depends_on = [azurerm_role_assignment.ado_profile_signer]
}

resource "azuredevops_project" "project" {
  count              = var.ado_enabled ? 1 : 0
  name               = var.ado_project_name
  description        = var.ado_project_description
  visibility         = var.ado_project_visibility
  version_control    = "Git"
  work_item_template = "Agile"
}

resource "azuredevops_git_repository" "repo" {
  count         = var.ado_enabled ? 1 : 0
  project_id    = azuredevops_project.project[0].id
  name          = var.ado_repo_name
  default_branch = "refs/heads/main"
  initialization {
    init_type = "Clean"
  }
}

resource "azuredevops_serviceendpoint_azurerm" "azurerm" {
  count                                 = var.ado_enabled ? 1 : 0
  project_id                             = azuredevops_project.project[0].id
  service_endpoint_name                  = var.ado_service_connection_name
  description                            = var.ado_service_connection_description
  service_endpoint_authentication_scheme = var.ado_service_endpoint_authentication_scheme

  dynamic "credentials" {
    for_each = var.ado_service_endpoint_authentication_scheme == "WorkloadIdentityFederation" ? [1] : []
    content {
      serviceprincipalid = local.ado_sp_client_id
    }
  }

  dynamic "credentials" {
    for_each = var.ado_service_endpoint_authentication_scheme == "ServicePrincipal" ? [1] : []
    content {
      serviceprincipalid  = local.ado_sp_client_id
      serviceprincipalkey = var.ado_service_principal_client_secret
    }
  }

  azurerm_spn_tenantid      = data.azurerm_client_config.current.tenant_id
  azurerm_subscription_id   = data.azurerm_subscription.current.subscription_id
  azurerm_subscription_name = data.azurerm_subscription.current.display_name

  features {
    validate = false
  }

  depends_on = [azuread_service_principal.ado_sp]
}

resource "azuredevops_variable_group" "signing" {
  count        = var.ado_enabled ? 1 : 0
  project_id   = azuredevops_project.project[0].id
  name         = "artifact-signing-demo"
  description  = "Managed by Terraform"
  allow_access = true

  variable {
    name  = "keyVaultName"
    value = var.keyvault_enabled ? local.keyvault_name_effective : ""
  }

  variable {
    name  = "artifactSigningEndpoint"
    value = local.artifact_signing_endpoint != null ? local.artifact_signing_endpoint : ""
  }

  variable {
    name  = "artifactSigningAccountName"
    value = azapi_resource.code_signing_account.name
  }

  variable {
    name  = "artifactSigningCertificateProfileName"
    value = var.certificate_profile_name
  }

  variable {
    name  = "artifactSigningResourceGroupName"
    value = azurerm_resource_group.rg.name
  }

  variable {
    name  = "artifactSigningCertificateProfileType"
    value = var.certificate_profile_type
  }

  variable {
    name  = "adoServicePrincipalObjectId"
    value = var.ado_create_app ? azuread_service_principal.ado_sp[0].object_id : ""
  }
}

resource "azuredevops_build_definition" "pipeline" {
  count      = var.ado_enabled ? 1 : 0
  project_id = azuredevops_project.project[0].id
  name       = var.ado_pipeline_name
  path       = "\\"

  repository {
    repo_type   = "TfsGit"
    repo_id     = azuredevops_git_repository.repo[0].id
    branch_name = azuredevops_git_repository.repo[0].default_branch
    yml_path    = var.ado_pipeline_yaml_path
  }

  ci_trigger {
    use_yaml = true
  }

  variable_groups = [
    azuredevops_variable_group.signing[0].id,
  ]

  features {
    skip_first_run = true
  }
}

resource "azuredevops_pipeline_authorization" "auth_endpoint" {
  count       = var.ado_enabled ? 1 : 0
  project_id  = azuredevops_project.project[0].id
  resource_id = azuredevops_serviceendpoint_azurerm.azurerm[0].id
  type        = "endpoint"
  pipeline_id = azuredevops_build_definition.pipeline[0].id
}

resource "azuredevops_pipeline_authorization" "auth_variablegroup" {
  count       = var.ado_enabled ? 1 : 0
  project_id  = azuredevops_project.project[0].id
  resource_id = azuredevops_variable_group.signing[0].id
  type        = "variablegroup"
  pipeline_id = azuredevops_build_definition.pipeline[0].id
}

resource "azuredevops_pipeline_authorization" "auth_repository" {
  count       = var.ado_enabled ? 1 : 0
  project_id  = azuredevops_project.project[0].id
  resource_id = azuredevops_git_repository.repo[0].id
  type        = "repository"
  pipeline_id = azuredevops_build_definition.pipeline[0].id
}
