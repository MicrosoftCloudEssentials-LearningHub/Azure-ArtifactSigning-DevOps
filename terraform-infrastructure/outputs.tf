output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "location" {
  value = azurerm_resource_group.rg.location
}

output "artifact_signing_account_id" {
  value = azapi_resource.code_signing_account.id
}

output "artifact_signing_account_name" {
  value = azapi_resource.code_signing_account.name
}

output "artifact_signing_endpoint" {
  value       = local.artifact_signing_endpoint
  description = "Region-specific endpoint used in metadata.json for signing."
}

output "certificate_profile_id" {
  value       = length(azapi_resource.certificate_profile) > 0 ? azapi_resource.certificate_profile[0].id : null
  description = "Certificate profile resource ID (null until identity_validation_id is provided)."
}

output "certificate_profile_name" {
  value       = length(azapi_resource.certificate_profile) > 0 ? azapi_resource.certificate_profile[0].name : null
  description = "Certificate profile name (null until created)."
}

output "github_app_client_id" {
  value       = var.github_enabled ? azuread_application.github_app[0].client_id : null
  description = "Client ID for the Entra app registration used by GitHub Actions (OIDC)."
}

output "github_sp_object_id" {
  value       = var.github_enabled ? azuread_service_principal.github_sp[0].object_id : null
  description = "Object ID for the GitHub Actions service principal (useful for troubleshooting RBAC)."
}

output "github_federated_subject" {
  value       = var.github_enabled ? local.github_fic_subject : null
  description = "Federated identity credential subject that must match the GitHub Actions workflow/ref."
}

output "keyvault_id" {
  value       = var.keyvault_enabled ? azurerm_key_vault.kv[0].id : null
  description = "Key Vault resource ID (null unless keyvault_enabled=true)."
}

output "keyvault_name" {
  value       = var.keyvault_enabled ? local.keyvault_name_effective : null
  description = "Key Vault name (null unless keyvault_enabled=true)."
}
