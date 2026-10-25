# ─── RDS PostgreSQL ───────────────────────────────────────────────────────────
# Private, encrypted, TLS-only, backed up, protected from deletion.
#
# Password handling (Terraform >= 1.11): an ephemeral random password is sent
# through write-only arguments to both RDS and SSM. It is never stored in state,
# plan files or git. Apps read it from SSM at container start.
# ─────────────────────────────────────────────────────────────────────────────

ephemeral "random_password" "db" {
  length  = 40
  special = false # alphanumeric: safe to drop into a connection URL without escaping
}

resource "aws_ssm_parameter" "password" {
  name             = var.password_ssm_parameter
  type             = "SecureString"
  value_wo         = ephemeral.random_password.db.result
  value_wo_version = var.password_version
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds"
  description = "RDS: ingress rules are added by the caller (app tasks, bastion)"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-rds" }
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.name}-db"
  subnet_ids = var.subnet_ids
}

resource "aws_db_parameter_group" "main" {
  name_prefix = "${var.name}-"
  family      = var.parameter_group_family

  parameter {
    name  = "rds.force_ssl"
    value = "1" # reject unencrypted connections
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # log queries slower than 1s
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "main" {
  identifier     = "${var.name}-db"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name                = var.db_name
  username               = var.username
  password_wo            = ephemeral.random_password.db.result
  password_wo_version    = var.password_version
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.main.name
  publicly_accessible    = false
  multi_az               = var.multi_az
  ca_cert_identifier     = "rds-ca-rsa2048-g1"

  storage_type          = "gp3"
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_encrypted     = true

  backup_retention_period    = var.backup_retention_days
  backup_window              = "03:00-04:00"         # UTC
  maintenance_window         = "sun:04:30-sun:05:30" # UTC, after backups
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true
  apply_immediately          = var.apply_immediately

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-db-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]
}
