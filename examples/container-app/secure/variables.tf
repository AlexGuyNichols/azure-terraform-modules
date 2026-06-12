variable "container_app_environment_id" {
  type        = string
  description = "Resource ID of the Container Apps Environment. The environment is caller-owned shared infrastructure (D-01) and is not provisioned by this example. This value is an Azure resource ID that embeds a subscription ID, which is why it is variable-driven rather than a tracked literal (D-10)."
}
