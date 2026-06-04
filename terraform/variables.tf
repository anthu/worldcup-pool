variable "snowflake_organization_name" {
  description = "Snowflake organization name"
  type        = string
}

variable "snowflake_account_name" {
  description = "Snowflake account name"
  type        = string
}

variable "snowflake_role" {
  description = "Role used for Terraform provisioning"
  type        = string
  default     = "ACCOUNTADMIN"
}

variable "database_name" {
  description = "Name of the provider database"
  type        = string
  default     = "WORLDCUP_POOL"
}

variable "warehouse_size" {
  description = "Size of the provider warehouse"
  type        = string
  default     = "XSMALL"
}

variable "compute_pool_name" {
  description = "Name of the SPCS compute pool"
  type        = string
  default     = "WORLDCUP_POOL_COMPUTE_POOL"
}

variable "football_data_token" {
  description = "API token for football-data.org"
  type        = string
  sensitive   = true
}
