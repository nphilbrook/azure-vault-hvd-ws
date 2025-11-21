variable "cert_email" {
  type    = string
  default = "nick.philbrook@hashicorp.com"
}

variable "tfe_organization" {
  type    = string
  default = "philbrook"
}

# Automatically added by HCP Terraform
variable "TFC_WORKSPACE_SLUG" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "vault_license" {
  type      = string
  sensitive = true
}

variable "manual_vm_count" {
  type    = number
  default = 0
}

variable "friendly_name_prefix" {
  type    = string
  default = "manual"
}