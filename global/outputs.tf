output "ecr_repository_urls" {
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
  description = "Map of repo key → URL. Environments read this via remote state"
}

output "certificate_arn" {
  value = aws_acm_certificate.main.arn
}

output "certificate_validation_records" {
  value = {
    for o in aws_acm_certificate.main.domain_validation_options : o.domain_name => {
      name  = o.resource_record_name
      type  = o.resource_record_type
      value = o.resource_record_value
    }
  }
  description = "Create these CNAMEs in your DNS provider, then apply with validate_certificate = true"
}

output "ci_deploy_role_arn" {
  value       = local.create_ci_role ? aws_iam_role.ci_deploy[0].arn : null
  description = "Use in GitHub Actions: aws-actions/configure-aws-credentials role-to-assume"
}
