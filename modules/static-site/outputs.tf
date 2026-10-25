output "bucket_name" {
  value = aws_s3_bucket.site.id
}

output "distribution_id" {
  value       = aws_cloudfront_distribution.site.id
  description = "For cache invalidation in CI"
}

output "distribution_domain_name" {
  value       = aws_cloudfront_distribution.site.domain_name
  description = "Point a CNAME (or Route 53 alias) for var.domain here"
}
