module "tls_certs_newer_global" {
  # Revert to this for Stacks unless they add an SSH key capability
  # source  = "app.terraform.io/philbrook/tls-azurerm/acme"
  # version = "0.0.3-alpha2"
  source = "git::ssh://git@github.com/hashicorp-services/terraform-acme-tls-azurerm.git//?ref=3c05ecb95c9f9f637f2c2bccaccce7a515e2fdaa"

  dns_zone_name                = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name
  dns_zone_resource_group_name = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.resource_group_name
  tls_cert_fqdn                = "vault.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name}"
  tls_cert_sans = [
    "vault-primary.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name}",
    "vault-dr.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name}",
  ]
  tls_cert_email_address = var.cert_email
  create_cert_files      = false
}

module "vault_prereqs" {
  # Revert to this for Stacks unless they add an SSH key capability
  # source  = "app.terraform.io/philbrook/prereqs/azurerm"
  # version = "1.0.1"
  source = "git::ssh://git@github.com/hashicorp-services/terraform-azurerm-prereqs.git//?ref=8186a6531d65c47614c5fcdf4a39c5a81569601e"

  # --- Common --- #
  friendly_name_prefix  = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.environment
  location              = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.location
  resource_group_name   = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.resource_group_name
  create_resource_group = false
  common_tags           = local.default_tags

  # --- DNS --- #
  # Created in azure-core-infra-ws since I needed it for TLS verification
  create_public_dns_zone = false
  # Created manually for global DNS
  create_private_dns_zone = false
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
  bastion_size           = "Standard_B2s_v2"

  # --- Key Vault "Bootstrap" Secrets --- #
  create_key_vault          = true
  kv_vault_license          = var.vault_license
  kv_vault_cert_base64      = module.tls_certs_newer_global.tls_fullchain_base64
  kv_vault_privkey_base64   = module.tls_certs_newer_global.tls_privkey_base64
  kv_vault_ca_bundle_base64 = module.tls_certs_newer_global.tls_ca_bundle_base64
}

# Auto-unseal key
# Requires a KVAP with GetRotationPolicy (and other stuff)
# Should probably make this depend on the full module above (KVAP needs to be created)
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

module "vault_prereqs_dr" {
  # Revert to this for Stacks unless they add an SSH key capability
  # source  = "app.terraform.io/philbrook/prereqs/azurerm"
  # version = "1.0.1"
  source = "git::ssh://git@github.com/hashicorp-services/terraform-azurerm-prereqs.git//?ref=8186a6531d65c47614c5fcdf4a39c5a81569601e"

  # --- Common --- #
  friendly_name_prefix  = "${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.dr.environment}dr"
  location              = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.dr.location
  resource_group_name   = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.dr.resource_group_name
  create_resource_group = false
  common_tags           = local.default_tags

  # --- DNS --- #
  # Created in azure-core-infra-ws since I needed it for TLS verification
  create_public_dns_zone = false
  # Created manually for global DNS
  create_private_dns_zone = false

  # Created in the HVD module
  create_private_dns_zone_vnet_link = false

  # --- Networking --- #
  create_vnet         = true
  create_nat_gateway  = true
  create_nsg_nat_rule = true
  create_bastion      = true
  vnet_cidr           = ["10.128.8.0/22"]
  bastion_subnet_cidr = "10.128.8.0/24"
  # Rolling with one subnet for everything
  # lb_subnet_cidr                 = "10.128.6.0/24"
  # Testing if a /26 will work for this
  vault_subnet_cidr              = "10.128.9.0/26"
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
  bastion_size           = "Standard_B2s_v2"

  # --- Key Vault "Bootstrap" Secrets --- #
  create_key_vault          = true
  kv_vault_license          = var.vault_license
  kv_vault_cert_base64      = module.tls_certs_newer_global.tls_fullchain_base64
  kv_vault_privkey_base64   = module.tls_certs_newer_global.tls_privkey_base64
  kv_vault_ca_bundle_base64 = module.tls_certs_newer_global.tls_ca_bundle_base64
}

# Auto-unseal key
# Requires a KVAP with GetRotationPolicy (and other stuff)
resource "azurerm_key_vault_key" "vault_unseal_key_dr" {
  name         = "vault-unseal-key-001"
  key_vault_id = module.vault_prereqs_dr.key_vault_id
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

  # A permission resource in this module must be in place before Terraform can create the key
  depends_on = [module.vault_prereqs_dr]
}

#------------------------------------------------------------------------------
# VNet Peering Between Central US and West Central US
#------------------------------------------------------------------------------

# Peering: Central US -> Canada Central
resource "azurerm_virtual_network_peering" "centralus_to_candacentral" {
  name                      = "peer-centralus-to-candacentral"
  resource_group_name       = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.resource_group_name
  virtual_network_name      = module.vault_prereqs.vnet_name
  remote_virtual_network_id = module.vault_prereqs_dr.vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# Peering: Canada Central -> Central US
resource "azurerm_virtual_network_peering" "candacentral_to_centralus" {
  name                      = "peer-candacentral-to-centralus"
  resource_group_name       = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.dr.resource_group_name
  virtual_network_name      = module.vault_prereqs_dr.vnet_name
  remote_virtual_network_id = module.vault_prereqs.vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
