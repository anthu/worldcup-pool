resource "snowflake_secret_with_generic_string" "football_data_token" {
  database      = snowflake_database.worldcup_pool.name
  schema        = snowflake_schema.provider.name
  name          = "FOOTBALL_DATA_TOKEN"
  secret_string = var.football_data_token
  comment       = "API token for football-data.org"
}
