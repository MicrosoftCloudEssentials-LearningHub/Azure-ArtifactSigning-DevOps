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

# If you want full portal access (Secrets/Keys/Certificates) without needing separate RBAC roles,
# grant the identity running `terraform apply` the Key Vault Administrator role.
keyvault_grant_administrator_to_current = true

# GitHub Actions OIDC (recommended)
# Set these to match your GitHub repo, so Terraform can create the federated identity credential.
github_enabled = false
github_owner   = "REPLACE_ME"
github_repo    = "Azure-ArtifactSigning-DevOps"
github_ref     = "refs/heads/main"
