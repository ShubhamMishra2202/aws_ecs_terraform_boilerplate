output "service_name" {
  value = var.create_service ? aws_ecs_service.this[0].name : null
}

output "task_definition_family" {
  value = aws_ecs_task_definition.this.family
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.this.name
}
