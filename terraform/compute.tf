resource "snowflake_warehouse" "worldcup_pool" {
  name           = "WORLDCUP_POOL_WH"
  warehouse_size = var.warehouse_size
  auto_suspend   = 60
  auto_resume    = true
  comment        = "Provider warehouse for score sync and app management"
}

resource "snowflake_compute_pool" "worldcup_pool" {
  name              = var.compute_pool_name
  instance_family   = "CPU_X64_XS"
  min_nodes         = 1
  max_nodes         = 1
  auto_suspend_secs = 3600
  auto_resume       = true
  comment           = "Compute pool for building/testing SPCS container images"
}
