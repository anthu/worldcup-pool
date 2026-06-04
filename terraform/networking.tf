resource "snowflake_network_rule" "football_data_egress" {
  database  = snowflake_database.worldcup_pool.name
  schema    = snowflake_schema.provider.name
  name      = "FOOTBALL_DATA_EGRESS_RULE"
  type      = "HOST_PORT"
  mode      = "EGRESS"
  value_list = ["api.football-data.org:443"]
  comment   = "Allow outbound HTTPS to football-data.org API"
}

resource "snowflake_external_access_integration" "football_data" {
  name               = "FOOTBALL_DATA_ACCESS_INTEGRATION"
  allowed_network_rules = ["${snowflake_database.worldcup_pool.name}.${snowflake_schema.provider.name}.${snowflake_network_rule.football_data_egress.name}"]
  allowed_authentication_secrets = ["${snowflake_database.worldcup_pool.name}.${snowflake_schema.provider.name}.${snowflake_secret_with_generic_string.football_data_token.name}"]
  enabled            = true
  comment            = "External access integration for football-data.org API"
}
