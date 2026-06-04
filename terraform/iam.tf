resource "snowflake_account_role" "app_role" {
  name    = "WORLDCUP_APP_ROLE"
  comment = "Role for the Native App package and runtime operations"
}

resource "snowflake_account_role" "admin_role" {
  name    = "WORLDCUP_ADMIN_ROLE"
  comment = "Admin role for managing the World Cup Pool provider infra"
}

# Grant admin role to current role hierarchy
resource "snowflake_grant_account_role" "admin_to_sysadmin" {
  role_name        = snowflake_account_role.admin_role.name
  parent_role_name = "SYSADMIN"
}

# Database grants
resource "snowflake_grant_privileges_to_account_role" "admin_db_usage" {
  account_role_name = snowflake_account_role.admin_role.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.worldcup_pool.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "app_db_usage" {
  account_role_name = snowflake_account_role.app_role.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.worldcup_pool.name
  }
}

# Schema grants - admin gets all schemas
resource "snowflake_grant_privileges_to_account_role" "admin_schema_raw" {
  account_role_name = snowflake_account_role.admin_role.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW"]
  on_schema {
    schema_name = "${snowflake_database.worldcup_pool.name}.${snowflake_schema.raw.name}"
  }
}

resource "snowflake_grant_privileges_to_account_role" "admin_schema_app" {
  account_role_name = snowflake_account_role.admin_role.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW"]
  on_schema {
    schema_name = "${snowflake_database.worldcup_pool.name}.${snowflake_schema.app.name}"
  }
}

resource "snowflake_grant_privileges_to_account_role" "admin_schema_provider" {
  account_role_name = snowflake_account_role.admin_role.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW", "CREATE PROCEDURE", "CREATE TASK"]
  on_schema {
    schema_name = "${snowflake_database.worldcup_pool.name}.${snowflake_schema.provider.name}"
  }
}

# App role gets read access to APP schema (for shared content)
resource "snowflake_grant_privileges_to_account_role" "app_schema_app" {
  account_role_name = snowflake_account_role.app_role.name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = "${snowflake_database.worldcup_pool.name}.${snowflake_schema.app.name}"
  }
}

# Warehouse grants
resource "snowflake_grant_privileges_to_account_role" "admin_wh_usage" {
  account_role_name = snowflake_account_role.admin_role.name
  privileges        = ["USAGE", "OPERATE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.worldcup_pool.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "app_wh_usage" {
  account_role_name = snowflake_account_role.app_role.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.worldcup_pool.name
  }
}

# Compute pool grants
resource "snowflake_grant_privileges_to_account_role" "admin_compute_pool" {
  account_role_name = snowflake_account_role.admin_role.name
  privileges        = ["USAGE", "OPERATE"]
  on_account_object {
    object_type = "COMPUTE POOL"
    object_name = snowflake_compute_pool.worldcup_pool.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "app_compute_pool" {
  account_role_name = snowflake_account_role.app_role.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "COMPUTE POOL"
    object_name = snowflake_compute_pool.worldcup_pool.name
  }
}
