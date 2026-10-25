# ─── App stack ────────────────────────────────────────────────────────────────
# Composes every module into one environment:
#
#   internet ─► ALB (public) ─► ECS web (private) ─► RDS (private)
#                               ECS worker ─────────┘
#   internet ─► CloudFront ─► S3 (private)
#   operator ─► SSM ─► bastion (private) ─► RDS
#   private  ─► NAT ─► internet (outbound only)
#
# Environments call this module with different sizes and safety flags.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  prefix     = "${var.name}-${var.environment}"
  ssm_prefix = "/${local.prefix}"
  image      = "${var.ecr_repository_url}:${var.image_tag}"

  # Connection details every container gets. The password comes from SSM.
  db_env = {
    DB_HOST = module.rds.address
    DB_PORT = tostring(module.rds.port)
    DB_NAME = module.rds.db_name
    DB_USER = module.rds.username
  }
  db_secrets = {
    DB_PASSWORD = module.rds.password_ssm_parameter
  }

  env_vars = merge(local.db_env, var.env_vars)
  secrets  = merge(local.db_secrets, var.secrets)
}

# ─── Network ──────────────────────────────────────────────────────────────────
module "vpc" {
  source   = "../vpc"
  name     = local.prefix
  cidr     = var.vpc_cidr
  azs      = var.azs
  nat_type = var.nat_type
}

module "alb" {
  source              = "../alb"
  name                = local.prefix
  vpc_id              = module.vpc.vpc_id
  vpc_cidr            = module.vpc.vpc_cidr
  public_subnet_ids   = module.vpc.public_subnet_ids
  certificate_arn     = var.certificate_arn
  target_port         = var.container_port
  health_check_path   = var.health_check_path
  deletion_protection = var.protect_from_deletion
}

# One SG shared by every app task (web, worker, migrate) so a single rule grants
# each of them database access.
resource "aws_security_group" "app" {
  name        = "${local.prefix}-app"
  description = "ECS tasks: ingress from ALB only, egress anywhere via NAT"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${local.prefix}-app" }
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  description       = "Outbound: RDS, AWS APIs, third-party APIs"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "ALB to container port"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = module.alb.security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_app" {
  security_group_id            = module.rds.security_group_id
  description                  = "App tasks to PostgreSQL"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_bastion" {
  count                        = var.enable_bastion ? 1 : 0
  security_group_id            = module.rds.security_group_id
  description                  = "Bastion to PostgreSQL"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = module.bastion[0].security_group_id
}

# ─── Data ─────────────────────────────────────────────────────────────────────
module "rds" {
  source                 = "../rds"
  name                   = local.prefix
  vpc_id                 = module.vpc.vpc_id
  subnet_ids             = module.vpc.private_subnet_ids
  instance_class         = var.db_instance_class
  allocated_storage      = var.db_allocated_storage
  max_allocated_storage  = var.db_max_allocated_storage
  engine_version         = var.db_engine_version
  parameter_group_family = var.db_parameter_group_family
  multi_az               = var.db_multi_az
  backup_retention_days  = var.db_backup_retention_days
  deletion_protection    = var.protect_from_deletion
  skip_final_snapshot    = !var.protect_from_deletion
  password_ssm_parameter = "${local.ssm_prefix}/db-password"
  password_version       = var.db_password_version
}

# ─── Compute ──────────────────────────────────────────────────────────────────
module "ecs_cluster" {
  source               = "../ecs-cluster"
  name                 = local.prefix
  container_insights   = var.container_insights
  ssm_parameter_prefix = local.ssm_prefix
}

module "web" {
  source = "../ecs-service"

  name               = "${local.prefix}-web"
  cluster_id         = module.ecs_cluster.cluster_id
  cluster_name       = module.ecs_cluster.cluster_name
  image              = local.image
  cpu                = var.cpu
  memory             = var.memory
  cpu_architecture   = var.cpu_architecture
  container_port     = var.container_port
  environment        = merge(local.env_vars, { PORT = tostring(var.container_port) })
  secrets            = local.secrets
  execution_role_arn = module.ecs_cluster.execution_role_arn
  task_role_arn      = module.ecs_cluster.task_role_arn
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [aws_security_group.app.id]
  target_group_arn   = module.alb.target_group_arn
  desired_count      = var.desired_count
  max_count          = var.max_count
  log_retention_days = var.log_retention_days

  # The target group must be attached to a listener before a service can use it.
  depends_on = [module.alb]
}

module "worker" {
  source = "../ecs-service"
  count  = var.worker_command != null ? 1 : 0

  name               = "${local.prefix}-worker"
  cluster_id         = module.ecs_cluster.cluster_id
  cluster_name       = module.ecs_cluster.cluster_name
  image              = local.image
  command            = var.worker_command
  cpu                = var.cpu
  memory             = var.memory
  cpu_architecture   = var.cpu_architecture
  environment        = local.env_vars
  secrets            = local.secrets
  execution_role_arn = module.ecs_cluster.execution_role_arn
  task_role_arn      = module.ecs_cluster.task_role_arn
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [aws_security_group.app.id]
  desired_count      = 1 # exactly one, so scheduled jobs never run twice
  log_retention_days = var.log_retention_days
}

module "migrate" {
  source = "../ecs-service"
  count  = var.migrate_command != null ? 1 : 0

  name               = "${local.prefix}-migrate"
  create_service     = false
  cluster_id         = module.ecs_cluster.cluster_id
  image              = local.image
  command            = var.migrate_command
  cpu_architecture   = var.cpu_architecture
  environment        = local.env_vars
  secrets            = local.secrets
  execution_role_arn = module.ecs_cluster.execution_role_arn
  task_role_arn      = module.ecs_cluster.task_role_arn
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [aws_security_group.app.id]
  log_retention_days = var.log_retention_days
}

# ─── Access ───────────────────────────────────────────────────────────────────
module "bastion" {
  source    = "../bastion"
  count     = var.enable_bastion ? 1 : 0
  name      = local.prefix
  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.private_subnet_ids[0]
}

# ─── Frontend ─────────────────────────────────────────────────────────────────
module "frontend" {
  source          = "../static-site"
  count           = var.frontend_domain != null ? 1 : 0
  name            = local.prefix
  domain          = var.frontend_domain
  certificate_arn = var.certificate_arn
  routing         = var.frontend_routing
  force_destroy   = !var.protect_from_deletion
}

# ─── Monitoring ───────────────────────────────────────────────────────────────
module "alarms" {
  source                  = "../alarms"
  name                    = local.prefix
  emails                  = var.alarm_emails
  alb_arn_suffix          = module.alb.arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  cluster_name            = module.ecs_cluster.cluster_name
  # Built from known strings so for_each works on the first plan.
  service_names = concat(
    ["${local.prefix}-web"],
    var.worker_command != null ? ["${local.prefix}-worker"] : [],
  )
  db_identifier = module.rds.identifier
}
