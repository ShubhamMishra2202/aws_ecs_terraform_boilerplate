# ─── Static site: private S3 + CloudFront ─────────────────────────────────────
# The bucket is never public. CloudFront reads it through Origin Access Control.
# Deploy: aws s3 sync ./dist s3://<bucket> --delete
#         aws cloudfront create-invalidation --distribution-id <id> --paths '/*'
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "site" {
  bucket        = "${var.name}-site"
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.name}-site"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Only this distribution may read the bucket.
resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontRead"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.site.arn}/*"
      Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.site.arn } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.site]
}

# static routing: /about → /about/index.html
resource "aws_cloudfront_function" "rewrite_index" {
  count   = var.routing == "static" ? 1 : 0
  name    = "${var.name}-rewrite-index"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-JS
    function handler(event) {
      var req = event.request;
      if (req.uri.endsWith('/')) { req.uri += 'index.html'; }
      else if (!req.uri.split('/').pop().includes('.')) { req.uri += '/index.html'; }
      return req;
    }
  JS
}

locals {
  # AWS managed policies
  caching_optimized_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  security_headers_policy_id  = "67f7725c-6f97-4210-82d7-5512b31e9d03" # HSTS, X-Frame-Options, nosniff, ...
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  aliases             = [var.domain]
  default_root_object = "index.html"
  price_class         = var.price_class

  origin {
    origin_id                = "s3"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id           = "s3"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = local.caching_optimized_policy_id
    response_headers_policy_id = local.security_headers_policy_id

    dynamic "function_association" {
      for_each = var.routing == "static" ? [1] : []
      content {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.rewrite_index[0].arn
      }
    }
  }

  # S3 returns 403 (not 404) for missing keys when the caller can't list the bucket.
  dynamic "custom_error_response" {
    for_each = [403, 404]
    content {
      error_code         = custom_error_response.value
      response_code      = var.routing == "spa" ? 200 : 404
      response_page_path = var.routing == "spa" ? "/index.html" : "/404.html"
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}
