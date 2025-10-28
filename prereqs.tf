module "tls_certs" {
  source  = "app.terraform.io/philbrook/tls-azurerm/acme"
  version = "0.0.2"

  dns_zone_name                = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.zone_name
  dns_zone_resource_group_name = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.resource_group_name
  tls_cert_fqdn                = "vault.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.zone_name}"
  tls_cert_email_address       = var.cert_email
  create_cert_files            = false
}

module "vault_prereqs" {
  source  = "app.terraform.io/philbrook/prereqs/azurerm"
  version = "0.0.4"

  # --- Common --- #
  friendly_name_prefix  = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.environment
  location              = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.location
  resource_group_name   = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.resource_group_name
  create_resource_group = false
  common_tags           = local.default_tags

  # --- DNS --- #
  create_public_dns_zone  = false
  public_dns_zone_name    = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.zone_name
  create_private_dns_zone = true
  # See if this works? Same name as public zone
  private_dns_zone_name = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.zone_name

  # --- Networking --- #
  create_vnet                    = true
  create_nat_gateway             = true
  create_nsg_nat_rule            = true
  create_bastion                 = true
  vnet_cidr                      = ["10.128.4.0/22"]
  bastion_subnet_cidr            = "10.128.5.0/24"
  lb_subnet_cidr                 = "10.128.6.0/24"
  vault_subnet_cidr              = "10.128.7.0/24"
  cidr_allow_ingress_bastion_ssh = data.tfe_outputs.azure_hcp_control_outputs.nonsensitive_values.ingress_ips
  cidr_allow_ingress_lb_443      = data.tfe_outputs.azure_hcp_control_outputs.nonsensitive_values.ingress_ips
  cidr_ingress_lb_allow_8200     = data.tfe_outputs.azure_hcp_control_outputs.nonsensitive_values.ingress_ips
  cidr_ingress_vault_allow_8200  = data.tfe_outputs.azure_hcp_control_outputs.nonsensitive_values.ingress_ips

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
  kv_vault_cert_base64      = module.tls_certs.tls_cert_base64
  kv_vault_privkey_base64   = module.tls_certs.tls_privkey_base64
  kv_vault_ca_bundle_base64 = module.tls_certs.tls_ca_bundle_base64
}

# Auto-unseal key
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
