# Demo-friendly defaults.
# NOTE: code_signing_account_name must be globally unique.

location                  = "eastus"
resource_group_name       = "RG-artifact-signing-demo"
code_signing_account_name = "aasdemo-replace-me"

# After you complete Identity validation in the Azure portal, paste the Identity validation Id here.
identity_validation_id = null

certificate_profile_name = "demo-code-signing"
certificate_profile_type = "PublicTrustTest"

# Key Vault for pipeline variables/secrets (enabled by default)
keyvault_enabled = true
# Optional override (must be globally unique):
# keyvault_name = "kvREPLACE_ME"

# Azure DevOps Workload Identity Federation (optional)
ado_enabled         = false
ado_org_service_url = "https://dev.azure.com/REPLACE_ME"

# Auth for the azuredevops provider is usually via PAT:
#   $env:AZDO_PERSONAL_ACCESS_TOKEN = "..."

ado_create_app = true

# If you set ado_service_endpoint_authentication_scheme = "ServicePrincipal",
# also set the secret via an env var instead of checking it in:
#   $env:TF_VAR_ado_service_principal_client_secret = "..."

# If ado_enabled=true and Terraform creates the service connection, Issuer/Subject are auto-populated.
ado_wif_issuer  = null
ado_wif_subject = null
