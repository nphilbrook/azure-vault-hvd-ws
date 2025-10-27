data "tfe_outputs" "azure_core_infra_outputs" {
  workspace = "azure-core-infra-ws"
}

data "tfe_outputs" "azure_hcp_control_outputs" {
  workspace = "azure-hcp-control"
}
