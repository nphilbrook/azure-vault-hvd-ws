# Removed from state but still valid for now until expiry. The DNS zone is gonezo.
# module "tls_certs" {
#   source  = "app.terraform.io/philbrook/tls-azurerm/acme"
#   version = "0.0.2"

#   dns_zone_name                = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.zone_name
#   dns_zone_resource_group_name = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.resource_group_name
#   tls_cert_fqdn                = "vault.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.zone_name}"
#   tls_cert_email_address       = var.cert_email
#   create_cert_files            = false
# }

module "tls_certs_new_global" {
  source  = "app.terraform.io/philbrook/tls-azurerm/acme"
  version = "0.0.3-alpha2"

  dns_zone_name                = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name
  dns_zone_resource_group_name = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.resource_group_name
  tls_cert_fqdn                = "vault.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name}"
  tls_cert_sans = [
    "vault-dr.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name}",
    "vault.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.zone_name}",
    "vault.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.eastus2.zone_name}",
    "vault-dr.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.zone_name}",
    "vault-dr.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.eastus2.zone_name}",
  ]
  tls_cert_email_address = var.cert_email
  create_cert_files      = false
}

module "vault_prereqs" {
  source  = "app.terraform.io/philbrook/prereqs/azurerm"
  version = "1.0.0"

  # --- Common --- #
  friendly_name_prefix  = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.environment
  location              = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.location
  resource_group_name   = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.resource_group_name
  create_resource_group = false
  common_tags           = local.default_tags

  # --- DNS --- #
  # Created in azure-core-infra-ws since I needed it for TLS verification
  create_public_dns_zone = false

  create_private_dns_zone = true
  # Kind of skeezy using the same name as the public zone, but we actually want them to be the same
  private_dns_zone_name = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.zone_name
  # Created in the HVD module
  create_private_dns_zone_vnet_link = false

  # --- Networking --- #
  create_vnet         = true
  create_nat_gateway  = true
  create_nsg_nat_rule = true
  create_bastion      = true
  vnet_cidr           = ["10.128.4.0/22"]
  bastion_subnet_cidr = "10.128.5.0/24"
  # Rolling with one subnet for everything
  # lb_subnet_cidr                 = "10.128.6.0/24"
  # Testing if a /25 will work for this
  vault_subnet_cidr              = "10.128.6.0/25"
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
  kv_vault_cert_base64      = base64encode(local.cert)
  kv_vault_privkey_base64   = base64encode(var.temp_cert_key)
  kv_vault_ca_bundle_base64 = base64encode(local.ca)
}

# Auto-unseal key
# Requires a KVAP with GetRotationPolicy (and other stuff)
resource "azurerm_key_vault_key" "vault_unseal_key" {
  name         = "vault-unseal-key-001"
  key_vault_id = module.vault_prereqs.key_vault_id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "encrypt",
    "decrypt",
    "sign",
    "verify",
    "wrapKey",
    "unwrapKey",
  ]
}

module "vault_prereqs_east2" {
  source  = "app.terraform.io/philbrook/prereqs/azurerm"
  version = "1.0.0"

  # --- Common --- #
  friendly_name_prefix  = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.eastus2.environment
  location              = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.eastus2.location
  resource_group_name   = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.eastus2.resource_group_name
  create_resource_group = false
  common_tags           = local.default_tags

  # --- DNS --- #
  # Created in azure-core-infra-ws since I needed it for TLS verification
  create_public_dns_zone = false

  create_private_dns_zone = true
  # Kind of skeezy using the same name as the public zone, but we actually want them to be the same
  private_dns_zone_name = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.eastus2.zone_name

  # Created in the HVD module
  create_private_dns_zone_vnet_link = false

  # --- Networking --- #
  create_vnet         = true
  create_nat_gateway  = true
  create_nsg_nat_rule = true
  create_bastion      = true
  vnet_cidr           = ["10.128.0.0/22"]
  bastion_subnet_cidr = "10.128.0.0/24"
  # Rolling with one subnet for everything
  # lb_subnet_cidr                 = "10.128.6.0/24"
  # Testing if a /26 will work for this
  vault_subnet_cidr              = "10.128.1.0/26"
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
  kv_vault_cert_base64      = module.tls_certs_new_global.tls_fullchain_base64
  kv_vault_privkey_base64   = module.tls_certs_new_global.tls_privkey_base64
  kv_vault_ca_bundle_base64 = module.tls_certs_new_global.tls_ca_bundle_base64
}

# Auto-unseal key
# Requires a KVAP with GetRotationPolicy (and other stuff)
resource "azurerm_key_vault_key" "vault_unseal_key_east2" {
  name         = "vault-unseal-key-001"
  key_vault_id = module.vault_prereqs_east2.key_vault_id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "encrypt",
    "decrypt",
    "sign",
    "verify",
    "wrapKey",
    "unwrapKey",
  ]
}
