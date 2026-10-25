# ─── Global ───────────────────────────────────────────────────────────────────
# Account-wide resources shared by every environment:
#   - ECR repositories  (one image, promoted staging → prod by tag)
#   - ACM certificate   (apex + wildcard, DNS-validated)
#   - GitHub OIDC role  (CI deploys without long-lived AWS keys)
# Environments read these through terraform_remote_state.
# ─────────────────────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

# ─── ECR ──────────────────────────────────────────────────────────────────────
resource "aws_ecr_repository" "this" {
  for_each = toset(var.ecr_repositories)

  name = "${var.name}-${each.key}"

  # MUTABLE so services can track a moving tag (:staging / :prod) and deploy with
  # `ecs update-service --force-new-deployment` — no Terraform in the deploy
  # path. CI also pushes an immutable :<git-sha> tag for rollbacks.
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the last ${var.ecr_keep_images} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.ecr_keep_images
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ─── ACM certificate ──────────────────────────────────────────────────────────
# DNS provider agnostic: create the records from the `certificate_validation_records`
# output in whatever DNS you use, then re-apply with validate_certificate = true.
# A wildcard covers ONE label only: api.example.com yes, api.staging.example.com no.
resource "aws_acm_certificate" "main" {
  domain_name               = var.domain
  subject_alternative_names = ["*.${var.domain}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "main" {
  count           = var.validate_certificate ? 1 : 0
  certificate_arn = aws_acm_certificate.main.arn
}

# ─── GitHub Actions OIDC deploy role ──────────────────────────────────────────
# CI exchanges a short-lived GitHub token for AWS credentials. No access keys to
# leak or rotate. Scoped to resources prefixed with var.name.
locals {
  create_ci_role = var.github_repository != null
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = local.create_ci_role ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "ci_deploy" {
  count = local.create_ci_role ? 1 : 0
  name  = "${var.name}-ci-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github[0].arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:*" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "ci_deploy" {
  count = local.create_ci_role ? 1 : 0
  name  = "deploy"
  role  = aws_iam_role.ci_deploy[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload",
          "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer", "ecr:InitiateLayerUpload",
          "ecr:PutImage", "ecr:UploadLayerPart",
        ]
        Resource = [for r in aws_ecr_repository.this : r.arn]
      },
      {
        Sid      = "EcsDeploy"
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices", "ecs:RunTask", "ecs:DescribeTasks"]
        Resource = "*"
        Condition = {
          ArnLike = { "ecs:cluster" = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${var.name}-*" }
        }
      },
      {
        Sid      = "EcsDescribeTaskDefinition"
        Effect   = "Allow"
        Action   = ["ecs:DescribeTaskDefinition"]
        Resource = "*"
      },
      {
        Sid      = "PassTaskRoles"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.name}-*"
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      },
      {
        Sid      = "StaticSiteSync"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["arn:aws:s3:::${var.name}-*-site", "arn:aws:s3:::${var.name}-*-site/*"]
      },
      {
        Sid      = "CloudFrontInvalidate"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
        Resource = "*"
      },
      {
        Sid      = "TailLogs"
        Effect   = "Allow"
        Action   = ["logs:GetLogEvents", "logs:FilterLogEvents"]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.name}-*"
      },
    ]
  })
}
