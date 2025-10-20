data "tfe_outputs" "azure_core_infra_outputs" {
  organization = "philbrook"
  workspace    = "azure-core-infra-ws"
}

module "tls_certs" {
  source  = "app.terraform.io/philbrook/tls-azurerm/acme"
  version = "0.0.2"

  dns_zone_name                = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.zone_name
  dns_zone_resource_group_name = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.resource_group_name
  tls_cert_fqdn                = "vault.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.zone_name}"
  tls_cert_email_address       = var.cert_email
  create_cert_files            = false
}
