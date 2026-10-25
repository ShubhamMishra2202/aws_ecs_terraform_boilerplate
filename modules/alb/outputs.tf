output "dns_name" {
  value = aws_lb.main.dns_name
}

output "zone_id" {
  value       = aws_lb.main.zone_id
  description = "For Route 53 alias records"
}

output "security_group_id" {
  value = aws_security_group.alb.id
}

output "target_group_arn" {
  value = aws_lb_target_group.app.arn
}

output "https_listener_arn" {
  value = aws_lb_listener.https.arn
}

output "arn_suffix" {
  value = aws_lb.main.arn_suffix
}

output "target_group_arn_suffix" {
  value = aws_lb_target_group.app.arn_suffix
}
