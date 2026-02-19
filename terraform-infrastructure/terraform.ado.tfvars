# Azure DevOps provisioning (optional)
# Use with:
#   terraform apply -var-file=terraform.tfvars -var-file=terraform.ado.tfvars
#
# Required environment variables for the azuredevops provider:
#   $env:AZDO_ORG_SERVICE_URL = "https://dev.azure.com/<your-org>"
#   $env:AZDO_PERSONAL_ACCESS_TOKEN = "<your-pat>"
#
# NOTE: Terraform can create the ADO project/repo/pipeline/service-connection,
# but it does not push this repo's contents into the new ADO repo.

ado_enabled = true

# If you prefer setting the org URL as a variable instead of env var, uncomment:
# ado_org_service_url = "https://dev.azure.com/<your-org>"

# Names (safe defaults)
ado_project_name   = "ArtifactSigningDemo"
ado_repo_name      = "Azure-ArtifactSigning-DevOps"
ado_pipeline_name  = "artifact-signing-demo"

# Service connection name MUST match azureServiceConnection in azure-pipelines.yml
ado_service_connection_name = "sc-artifact-signing"

# Default: secretless auth (requires org feature enabled)
ado_service_endpoint_authentication_scheme = "WorkloadIdentityFederation"

# If your org can't use WIF yet, switch to ServicePrincipal and provide the secret via:
#   $env:TF_VAR_ado_service_principal_client_secret = "..."
# ado_service_endpoint_authentication_scheme = "ServicePrincipal"
