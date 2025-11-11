locals {
  prefix = "devss"
}

# This cluster was for testing Azure LB health probe's behavior with a self-signed cert. It worked fine. Left in comment for posterity

#------------------------------------------------------------------------------
# Azure Load Balancer
#------------------------------------------------------------------------------
# resource "azurerm_lb" "vault_ss" {
#   name                = "${local.prefix}-vault-lb"
#   resource_group_name = local.resource_group_name
#   location            = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.location
#   sku                 = "Standard"
#   sku_tier            = "Regional"

#   frontend_ip_configuration {
#     name                          = "vault-frontend-${local.prefix}"
#     zones                         = ["1", "2", "3"]
#     subnet_id                     = module.vault_prereqs.vault_subnet_id
#     private_ip_address_allocation = "Dynamic"
#   }

#   tags = merge(
#     { "Name" = "${local.prefix}-vault-lb" },
#     local.default_tags
#   )
# }

# resource "azurerm_lb_backend_address_pool" "vault_servers_ss" {
#   name            = "${local.prefix}-vault-backend"
#   loadbalancer_id = azurerm_lb.vault_ss.id
# }

# resource "azurerm_lb_probe" "vault" {
#   name                = "${local.prefix}-vault-lb-probe"
#   loadbalancer_id     = azurerm_lb.vault_ss.id
#   protocol            = "Https"
#   port                = 8200
#   request_path        = "/v1/sys/health?perfstandbyok=1&uninitcode=200&drsecondarycode=200"
#   interval_in_seconds = 15
# }

# resource "azurerm_lb_rule" "vault_8200" {
#   name                           = "${local.prefix}-vault-lb-rule-8200"
#   loadbalancer_id                = azurerm_lb.vault_ss.id
#   probe_id                       = azurerm_lb_probe.vault.id
#   protocol                       = "Tcp"
#   frontend_ip_configuration_name = azurerm_lb.vault_ss.frontend_ip_configuration[0].name
#   frontend_port                  = 8200
#   backend_address_pool_ids       = [azurerm_lb_backend_address_pool.vault_servers_ss.id]
#   backend_port                   = 8200
# }

# resource "azurerm_network_interface" "vault_nic_ss" {
#   resource_group_name = local.resource_group_name
#   location            = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.location
#   name                = "${local.prefix}-vault-vm-nic"

#   ip_configuration {
#     name                          = "internal"
#     subnet_id                     = module.vault_prereqs.vault_subnet_id
#     private_ip_address_allocation = "Dynamic"
#   }
#   tags = merge(
#     # CRITICAL - this tag is critical for the auto-join feature to work
#     { "VaultCluster" = local.prefix },
#     local.default_tags
#   )
# }

# resource "azurerm_lb_backend_address_pool_address" "vault_pool_address_ss" {
#   name                    = "${local.prefix}-vault-lb-backend"
#   backend_address_pool_id = azurerm_lb_backend_address_pool.vault_servers_ss.id
#   virtual_network_id      = module.vault_prereqs.vnet_id
#   ip_address              = azurerm_network_interface.vault_nic_ss.private_ip_address
# }

# resource "azurerm_linux_virtual_machine" "vault_vm_ss" {
#   name                = "${local.prefix}-vault"
#   resource_group_name = local.resource_group_name
#   location            = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.location

#   size           = "Standard_D2s_v5"
#   admin_username = "vaultadmin"

#   zone = "3"

#   identity {
#     type         = "UserAssigned"
#     identity_ids = ["/subscriptions/9d1e3560-fd29-4207-be8f-c6f9f0f1b64d/resourceGroups/dev-centralus/providers/Microsoft.ManagedIdentity/userAssignedIdentities/dev-vault-msi"]
#   }

#   admin_ssh_key {
#     username   = "vaultadmin"
#     public_key = var.ssh_public_key
#   }

#   source_image_reference {
#     publisher = "RedHat"
#     offer     = "RHEL"
#     sku       = "95_gen2"
#     version   = data.azurerm_platform_image.latest_os_image.version
#   }

#   network_interface_ids = [
#     azurerm_network_interface.vault_nic_ss.id,
#   ]

#   os_disk {
#     caching              = "ReadWrite"
#     storage_account_type = "Premium_LRS"
#     disk_size_gb         = "64"
#   }

#   tags = merge(
#     { "Name" = "${local.prefix}-vault" },
#     { "VaultCluster" = "devss" },
#     local.default_tags
#   )
# }

# resource "azurerm_managed_disk" "vault_data_ss" {
#   name                 = "${local.prefix}-vault-data-disk"
#   location             = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.location
#   resource_group_name  = local.resource_group_name
#   storage_account_type = "Premium_LRS"
#   create_option        = "Empty"
#   disk_size_gb         = "200"
#   zone                 = "3"

#   tags = local.default_tags
# }

# resource "azurerm_virtual_machine_data_disk_attachment" "vault_data_attachment_ss" {
#   managed_disk_id    = azurerm_managed_disk.vault_data_ss.id
#   virtual_machine_id = azurerm_linux_virtual_machine.vault_vm_ss.id
#   lun                = "0"
#   caching            = "ReadWrite"
# }
