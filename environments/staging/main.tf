# ─── Staging ──────────────────────────────────────────────────────────────────
# Same stack as prod, smaller and disposable. Catches problems before prod does.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  name   = "myapp"
  domain = "example.com"
}

module "stack" {
  source = "../../modules/app-stack"

  name        = local.name
  environment = "staging"

  ecr_repository_url = data.terraform_remote_state.global.outputs.ecr_repository_urls["app"]
  certificate_arn    = data.terraform_remote_state.global.outputs.certificate_arn

  vpc_cidr = "10.0.0.0/16" # prod uses 10.1.0.0/16, never overlap
  nat_type = "instance"

  image_tag         = "staging"
  container_port    = 8080
  health_check_path = "/health"
  cpu               = 256
  memory            = 512
  desired_count     = 1

  env_vars = {
    APP_ENV      = "staging"
    FRONTEND_URL = "https://app-staging.${local.domain}"
  }

  # Create these in SSM (SecureString) before applying:
  #   aws ssm put-parameter --type SecureString --name /myapp-staging/app-secret --value ...
  secrets = {
    # APP_SECRET = "/myapp-staging/app-secret"
  }

  worker_command  = null # e.g. ["node", "dist/worker.js"]
  migrate_command = null # e.g. ["npm", "run", "migrate"]

  db_instance_class        = "db.t4g.micro"
  db_backup_retention_days = 3
  db_multi_az              = false

  protect_from_deletion = false # staging can be torn down
  log_retention_days    = 7

  frontend_domain = "app-staging.${local.domain}"
  enable_bastion  = true
  alarm_emails    = []
}
