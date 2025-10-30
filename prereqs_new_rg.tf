module "tls_certs_2" {
  source  = "app.terraform.io/philbrook/tls-azurerm/acme"
  version = "0.0.2"

  dns_zone_name                = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.zone_name
  dns_zone_resource_group_name = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.resource_group_name
  tls_cert_fqdn                = "vault-secondary.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.zone_name}"
  tls_cert_email_address       = var.cert_email
  create_cert_files            = false
}

module "vault_prereqs_2" {
  source  = "app.terraform.io/philbrook/prereqs/azurerm"
  version = "1.0.0"

  # --- Common --- #
  friendly_name_prefix  = "secondary"
  location              = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.location
  resource_group_name   = "secondary"
  create_resource_group = true
  common_tags           = local.default_tags

  # --- DNS --- #
  # Created in azure-core-infra-ws since I needed it for TLS verification
  create_public_dns_zone = false

  create_private_dns_zone           = true
  private_dns_zone_name             = "secondary.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.zone_name}"
  create_private_dns_zone_vnet_link = true

  # --- Networking --- #
  create_vnet         = true
  create_nat_gateway  = true
  create_nsg_nat_rule = true
  create_bastion      = true
  vnet_cidr           = ["10.128.8.0/22"]
  bastion_subnet_cidr = "10.128.9.0/24"
  # Rolling with one subnet for everything
  # lb_subnet_cidr                 = "10.128.6.0/24"
  # Testing if a /25 will work for this
  vault_subnet_cidr              = "10.128.10.0/25"
  cidr_allow_ingress_bastion_ssh = data.tfe_outputs.azure_hcp_control_outputs.nonsensitive_values.ingress_ips

  # Will get to all of these through the bastion for now
  # cidr_allow_ingress_lb_443      = data.tfe_outputs.azure_hcp_control_outputs.nonsensitive_values.ingress_ips
  # cidr_ingress_lb_allow_8200     = data.tfe_outputs.azure_hcp_control_outputs.nonsensitive_values.ingress_ips
  # cidr_ingress_vault_allow_8200  = data.tfe_outputs.azure_hcp_control_outputs.nonsensitive_values.ingress_ips

  # Taking a Zero-Trust posture here, since I'm using HCPt's global agent pool
  # To lock this down, would need to run HCPt agents somewhere and allow-list those IPs
  # in the 2nd variable
  network_default_action       = "Allow"
  key_vault_cidr_allow_ingress = [] # do I need this?

  # Bastion
  bastion_ssh_public_key = var.ssh_public_key
  bastion_size           = "Standard_B2s"

  # --- Key Vault "Bootstrap" Secrets --- #
  create_key_vault          = true
  kv_vault_license          = var.vault_license
  kv_vault_cert_base64      = module.tls_certs_2.tls_fullchain_base64
  kv_vault_privkey_base64   = module.tls_certs_2.tls_privkey_base64
  kv_vault_ca_bundle_base64 = module.tls_certs_2.tls_ca_bundle_base64
}
