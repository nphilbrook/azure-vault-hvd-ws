output "vault_cli_config" {
  value = nonsensitive(module.vault_hvd.vault_cli_config)
}
