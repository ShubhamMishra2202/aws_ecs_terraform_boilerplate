# ─── Production ───────────────────────────────────────────────────────────────

locals {
  name   = "myapp"
  domain = "example.com"
}

module "stack" {
  source = "../../modules/app-stack"

  name        = local.name
  environment = "prod"

  ecr_repository_url = data.terraform_remote_state.global.outputs.ecr_repository_urls["app"]
  certificate_arn    = data.terraform_remote_state.global.outputs.certificate_arn

  vpc_cidr = "10.1.0.0/16"
  nat_type = "gateway" # managed and highly available; "instance" saves ~$28/mo

  image_tag          = "prod"
  container_port     = 8080
  health_check_path  = "/health"
  cpu                = 512
  memory             = 1024
  desired_count      = 2 # two tasks across two AZs
  max_count          = 4 # autoscale on CPU/memory
  container_insights = "enabled"

  env_vars = {
    APP_ENV      = "production"
    FRONTEND_URL = "https://app.${local.domain}"
  }

  secrets = {
    # APP_SECRET = "/myapp-prod/app-secret"
  }

  worker_command  = null
  migrate_command = null

  db_instance_class        = "db.t4g.small"
  db_allocated_storage     = 50
  db_max_allocated_storage = 200
  db_backup_retention_days = 14
  db_multi_az              = true # survives an AZ outage

  protect_from_deletion = true
  log_retention_days    = 30

  frontend_domain = "app.${local.domain}"
  enable_bastion  = true
  alarm_emails    = ["oncall@example.com"]
}
