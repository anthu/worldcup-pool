output "database_name" {
  description = "Name of the provider database"
  value       = snowflake_database.worldcup_pool.name
}

output "warehouse_name" {
  description = "Name of the provider warehouse"
  value       = snowflake_warehouse.worldcup_pool.name
}

output "compute_pool_name" {
  description = "Name of the SPCS compute pool"
  value       = snowflake_compute_pool.worldcup_pool.name
}

output "image_repository_url" {
  description = "URL of the image repository for docker push"
  value       = snowflake_image_repository.worldcup_pool.repository_url
}

output "external_access_integration_name" {
  description = "Name of the external access integration for football-data.org"
  value       = snowflake_external_access_integration.football_data.name
}

output "admin_role_name" {
  description = "Name of the admin role"
  value       = snowflake_account_role.admin_role.name
}

output "app_role_name" {
  description = "Name of the app role"
  value       = snowflake_account_role.app_role.name
}
