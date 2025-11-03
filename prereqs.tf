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

module "tls_certs_newer_global" {
  source  = "app.terraform.io/philbrook/tls-azurerm/acme"
  version = "0.0.3-alpha2"

  dns_zone_name                = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name
  dns_zone_resource_group_name = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.resource_group_name
  tls_cert_fqdn                = "vault.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name}"
  tls_cert_sans = [
    "vault-dr.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name}",
    "vault.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.zone_name}",
    "vault.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.eastus2.zone_name}",
    "vault.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.dr.zone_name}",
    "vault-dr.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.zone_name}",
    "vault-dr.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.eastus2.zone_name}",
    "vault-dr.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.dr.zone_name}",
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
  kv_vault_cert_base64      = module.tls_certs_new_global.tls_fullchain_base64
  kv_vault_privkey_base64   = module.tls_certs_new_global.tls_privkey_base64
  kv_vault_ca_bundle_base64 = module.tls_certs_new_global.tls_ca_bundle_base64
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

module "vault_prereqs_east2" {
  source  = "app.terraform.io/philbrook/prereqs/azurerm"
  version = "1.0.0"

  # --- Common --- #
  friendly_name_prefix  = "${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.eastus2.environment}dr"
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
# Should probably make this depend on the full module above (KVAP needs to be created)
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

module "vault_prereqs_dr" {
  source  = "app.terraform.io/philbrook/prereqs/azurerm"
  version = "1.0.0"

  # --- Common --- #
  friendly_name_prefix  = "${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.dr.environment}dr"
  location              = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.dr.location
  resource_group_name   = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.dr.resource_group_name
  create_resource_group = false
  common_tags           = local.default_tags

  # --- DNS --- #
  # Created in azure-core-infra-ws since I needed it for TLS verification
  create_public_dns_zone = false

  create_private_dns_zone = true
  # Kind of skeezy using the same name as the public zone, but we actually want them to be the same
  private_dns_zone_name = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.dr.zone_name

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
resource "azurerm_key_vault_key" "vault_unseal_key_westcentral" {
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

# Peering: Central US -> West Central US
resource "azurerm_virtual_network_peering" "centralus_to_westcentralus" {
  name                      = "peer-centralus-to-westcentralus"
  resource_group_name       = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.resource_group_name
  virtual_network_name      = module.vault_prereqs.vnet_name
  remote_virtual_network_id = module.vault_prereqs_dr.vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# Peering: West Central US -> Central US
resource "azurerm_virtual_network_peering" "westcentralus_to_centralus" {
  name                      = "peer-westcentralus-to-centralus"
  resource_group_name       = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.dr.resource_group_name
  virtual_network_name      = module.vault_prereqs_dr.vnet_name
  remote_virtual_network_id = module.vault_prereqs.vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

#------------------------------------------------------------------------------
# NSG Rules for Cross-Region Vault Communication
#------------------------------------------------------------------------------

# # Central US: Allow inbound 8200 and 8201 from East US 2 vault subnet
# resource "azurerm_network_security_rule" "centralus_allow_eastus2_vault_replication" {
#   name                        = "AllowEastUS2VaultReplication"
#   priority                    = 150
#   direction                   = "Inbound"
#   access                      = "Allow"
#   protocol                    = "Tcp"
#   source_port_range           = "*"
#   destination_port_ranges     = ["8200", "8201"]
#   source_address_prefix       = "10.128.1.0/26" # East US 2 vault subnet
#   destination_address_prefix  = "10.128.6.0/25" # Central US vault subnet
#   resource_group_name         = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.resource_group_name
#   network_security_group_name = module.vault_prereqs.vault_nsg_name
# }

# # East US 2: Allow inbound 8200 and 8201 from Central US vault subnet
# resource "azurerm_network_security_rule" "eastus2_allow_centralus_vault_replication" {
#   name                        = "AllowCentralUSVaultReplication"
#   priority                    = 150
#   direction                   = "Inbound"
#   access                      = "Allow"
#   protocol                    = "Tcp"
#   source_port_range           = "*"
#   destination_port_ranges     = ["8200", "8201"]
#   source_address_prefix       = "10.128.6.0/25" # Central US vault subnet
#   destination_address_prefix  = "10.128.1.0/26" # East US 2 vault subnet
#   resource_group_name         = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.eastus2.resource_group_name
#   network_security_group_name = module.vault_prereqs_east2.vault_nsg_name
# }

# # Central US: Deny all other traffic from East US 2 VNet
# resource "azurerm_network_security_rule" "centralus_deny_other_eastus2" {
#   name                        = "DenyOtherEastUS2Traffic"
#   priority                    = 4090
#   direction                   = "Inbound"
#   access                      = "Deny"
#   protocol                    = "*"
#   source_port_range           = "*"
#   destination_port_range      = "*"
#   source_address_prefix       = "10.128.0.0/22" # East US 2 VNet
#   destination_address_prefix  = "*"
#   resource_group_name         = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.resource_group_name
#   network_security_group_name = module.vault_prereqs.vault_nsg_name
# }

# # East US 2: Deny all other traffic from Central US VNet
# resource "azurerm_network_security_rule" "eastus2_deny_other_centralus" {
#   name                        = "DenyOtherCentralUSTraffic"
#   priority                    = 4090
#   direction                   = "Inbound"
#   access                      = "Deny"
#   protocol                    = "*"
#   source_port_range           = "*"
#   destination_port_range      = "*"
#   source_address_prefix       = "10.128.4.0/22" # Central US VNet
#   destination_address_prefix  = "*"
#   resource_group_name         = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.eastus2.resource_group_name
#   network_security_group_name = module.vault_prereqs_east2.vault_nsg_name
# }
