resource "snowflake_database" "worldcup_pool" {
  name    = var.database_name
  comment = "World Cup Prediction Pool - Provider database"
}

resource "snowflake_schema" "raw" {
  database = snowflake_database.worldcup_pool.name
  name     = "RAW"
  comment  = "Raw ingested data from football-data.org"
}

resource "snowflake_schema" "app" {
  database = snowflake_database.worldcup_pool.name
  name     = "APP"
  comment  = "Application package content and shared data"
}

resource "snowflake_schema" "provider" {
  database = snowflake_database.worldcup_pool.name
  name     = "PROVIDER"
  comment  = "Provider-side sync logic and staging"
}
