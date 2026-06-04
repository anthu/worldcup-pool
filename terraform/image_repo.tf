resource "snowflake_image_repository" "worldcup_pool" {
  database = snowflake_database.worldcup_pool.name
  schema   = snowflake_schema.app.name
  name     = "IMAGE_REPO"
  comment  = "Container image repository for the World Cup Pool SPCS service"
}
