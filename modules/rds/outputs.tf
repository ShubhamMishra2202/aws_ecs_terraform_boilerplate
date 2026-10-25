output "identifier" {
  value = aws_db_instance.main.identifier
}

output "address" {
  value = aws_db_instance.main.address
}

output "port" {
  value = aws_db_instance.main.port
}

output "db_name" {
  value = aws_db_instance.main.db_name
}

output "username" {
  value = aws_db_instance.main.username
}

output "password_ssm_parameter" {
  value = aws_ssm_parameter.password.name
}

output "security_group_id" {
  value = aws_security_group.rds.id
}
