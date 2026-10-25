# Outputs are the hand-off to DNS and CI. Copy them into your pipeline's variables.

output "api_dns_target" {
  value       = module.alb.dns_name
  description = "CNAME your API hostname here"
}

output "frontend_dns_target" {
  value       = one(module.frontend[*].distribution_domain_name)
  description = "CNAME frontend_domain here"
}

output "frontend_bucket" {
  value = one(module.frontend[*].bucket_name)
}

output "frontend_distribution_id" {
  value = one(module.frontend[*].distribution_id)
}

output "ecs_cluster_name" {
  value = module.ecs_cluster.cluster_name
}

output "web_service_name" {
  value = module.web.service_name
}

output "worker_service_name" {
  value = one(module.worker[*].service_name)
}

output "migrate_task_family" {
  value = one(module.migrate[*].task_definition_family)
}

output "private_subnet_ids" {
  value       = join(",", module.vpc.private_subnet_ids)
  description = "For `aws ecs run-task --network-configuration`"
}

output "app_security_group_id" {
  value       = aws_security_group.app.id
  description = "For `aws ecs run-task --network-configuration`"
}

output "task_role_name" {
  value       = module.ecs_cluster.task_role_name
  description = "Attach app permissions (S3, SES, SQS...) to this role"
}

output "db_address" {
  value = module.rds.address
}

output "db_password_ssm_parameter" {
  value = module.rds.password_ssm_parameter
}

output "bastion_instance_id" {
  value = one(module.bastion[*].instance_id)
}

output "nat_public_ip" {
  value = module.vpc.nat_public_ip
}

output "alarm_topic_arn" {
  value = module.alarms.sns_topic_arn
}
