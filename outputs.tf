output "vault_cli_config" {
  value     = module.vault_hvd.vault_cli_config
  sensitive = true
}