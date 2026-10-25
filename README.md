# AWS Container App: Terraform Boilerplate

A reusable baseline for running a containerised web app on AWS: an API on ECS
Fargate behind an ALB, PostgreSQL on RDS, an optional worker, one-off migration
task, and static frontend, with staging and prod built from the same modules.

```
                  ┌──────────────── VPC ─────────────────────────────────┐
internet ─► ALB ──┼─► ECS web (private) ──┐                              │
  (public subnet) │   ECS worker ─────────┼─► RDS Postgres (private)     │
                  │   ECS migrate (1-off)─┘      ▲                       │
operator ─► SSM ──┼─► bastion (private) ─────────┘                       │
                  │   private subnets ─► NAT ─► internet (outbound only) │
                  └──────────────────────────────────────────────────────┘
internet ─► CloudFront ─► S3 (private, OAC)
```

## Layout

```
bootstrap/            S3 state bucket (local state, run once per account)
global/               ECR repos, ACM cert, GitHub OIDC deploy role (shared by all envs)
environments/
  staging/            ~70 lines: calls modules/app-stack with small, disposable settings
  prod/               ~70 lines: same stack, bigger, protected
modules/
  app-stack/          wires everything below into one environment
  vpc/                public + private subnets over N AZs, NAT (instance or gateway)
  alb/                HTTPS listener, HTTP→HTTPS redirect, target group
  ecs-cluster/        cluster + execution role + task role
  ecs-service/        one module for web (ALB + autoscaling), worker, or one-off task
  rds/                Postgres, encrypted, TLS-only, password via write-only args
  bastion/            SSM-only access box, no SSH key or open ports
  static-site/        private S3 + CloudFront (SPA or static-export routing)
  alarms/             5xx, no healthy targets, latency, ECS CPU/mem, RDS CPU/storage → SNS
```

## Good practices built in

| Area | Practice |
|---|---|
| State | Remote S3 state, versioned, encrypted, TLS-only; native S3 locking (`use_lockfile`), so no DynamoDB |
| Blast radius | Separate state per layer: bootstrap → global → each environment |
| DRY | Environments are thin wrappers around one `app-stack` module, so staging can't drift from prod |
| Network | App and DB in private subnets; security groups reference each other, never broad CIDRs; default SG stripped |
| Secrets | Never in git or tfvars. App secrets live in SSM; the DB password is generated ephemerally and sent via write-only args, so it's **never in state** |
| IAM | Separate execution and task roles; execution role can read only `/<name>-<env>/*`; CI uses GitHub OIDC, no access keys |
| TLS | ALB TLS 1.2/1.3 policy, HTTP→HTTPS redirect, CloudFront TLSv1.2_2021 + security headers, RDS `force_ssl` |
| Deploys | Rolling deploys, circuit breaker with auto-rollback, deploy doesn't need Terraform |
| Data safety | `protect_from_deletion` toggles RDS/ALB deletion protection, final snapshot and S3 force-destroy in one place |
| Hardening | IMDSv2 only, encrypted volumes, private S3 with OAC, ECR scan-on-push, `drop_invalid_header_fields` |
| Ops | Log retention set, storage autoscaling, minimum alarm set, outputs are the CI hand-off |

## Is this too much for your app?

Open [docs/hosting-options.html](docs/hosting-options.html) in a browser. It
compares what this template deploys with leaner variations (external database,
no NAT, API Gateway instead of an ALB, a single EC2 box), with monthly cost,
resource count and trade-offs for each. Only the "as shipped" scenario exists in
this repo; the others need Terraform changes, which the page lists.

## First-time setup

Requires Terraform **>= 1.11** and AWS credentials.

1. **Rename.** Replace `myapp` and `example.com` in `environments/*/main.tf`.
2. **Bootstrap state.**
   ```bash
   cd bootstrap && terraform init && terraform apply -var name=myapp
   ```
   Put the `state_bucket` output in place of `REPLACE_ME_STATE_BUCKET` in every `backend.tf` (4 places).
3. **Global.**
   ```bash
   cd global && cp terraform.tfvars.example terraform.tfvars   # edit it
   terraform init && terraform apply
   ```
   Create the `certificate_validation_records` CNAMEs in your DNS, set
   `validate_certificate = true`, and apply again.
4. **Push a first image.** The services track a moving tag and fail to start without it:
   ```bash
   docker build -t <ecr_url>:staging . && docker push <ecr_url>:staging
   ```
5. **Create app secrets in SSM** under `/myapp-staging/…` (see `secrets` in `main.tf`).
6. **Apply the environment.**
   ```bash
   cd environments/staging && terraform init && terraform apply
   ```
7. **DNS.** CNAME your API host → `api_dns_target`, and the frontend host → `frontend_dns_target`.
8. **CI.** Copy `terraform output -json stack` values into your pipeline variables.

Repeat 4–8 for `prod`.

## How the app gets configured

Every container (web, worker, migrate) receives:

| Var | Source |
|---|---|
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` | Terraform (plain env) |
| `DB_PASSWORD` | SSM `/<name>-<env>/db-password`, injected at start |
| `PORT` (web only) | `container_port` |
| your `env_vars` / `secrets` | `environments/*/main.tf` |

Need a single `DATABASE_URL`? Compose it in the container entrypoint:
`export DATABASE_URL="postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME?sslmode=require"`

Rotate the DB password: bump `db_password_version`, apply, then restart the services.

## Deploy flow (CI, no Terraform)

```bash
# 1. build + push: moving tag for the service, immutable SHA tag for rollback
docker build -t $ECR:prod -t $ECR:$GIT_SHA . && docker push --all-tags $ECR

# 2. migrations (if migrate_command is set). Stop here if exit code != 0
aws ecs run-task --cluster <ecs_cluster_name> --task-definition <migrate_task_family> \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[<private_subnet_ids>],securityGroups=[<app_security_group_id>]}"

# 3. roll the services onto the new image
aws ecs update-service --cluster <cluster> --service <web_service_name> --force-new-deployment

# rollback = re-point :prod at an old SHA's manifest, then step 3
```

Frontend: `aws s3 sync dist/ s3://<frontend_bucket> --delete` then
`aws cloudfront create-invalidation --distribution-id <id> --paths '/*'`.

## Database access

```bash
aws ssm start-session --target <bastion_instance_id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters host=<db_address>,portNumber=5432,localPortNumber=5433
psql "host=localhost port=5433 dbname=app user=app_admin sslmode=require"
```
Needs the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html).

## Knobs worth knowing

| Setting | Staging default | Prod default | Why |
|---|---|---|---|
| `nat_type` | `instance` (~$4/mo) | `gateway` (~$32/mo) | cost vs. single point of failure |
| `db_multi_az` | false | true | survive an AZ outage (~2× DB cost) |
| `desired_count` / `max_count` | 1 / none | 2 / 4 | availability + autoscaling |
| `protect_from_deletion` | false | true | one flag for all destroy guards |
| `cpu_architecture` | X86_64 | X86_64 | `ARM64` is ~20% cheaper if your image supports it |

## Constraints

- **Names:** keep `name-environment` ≤ ~20 chars. ALB and target group names are capped at 32.
- **Region:** CloudFront certificates must be in `us-east-1`. For another region, add a
  `us-east-1` provider alias in `global/` for a second certificate.
- **Wildcard certs cover one label:** `api-staging.example.com` works, `api.staging.example.com` doesn't.
- **CIDRs** must not overlap between environments if you ever want VPC peering.
- `vpc_cidr` changes rebuild the network; `db_instance_class` changes reboot the DB
  (in the maintenance window unless `apply_immediately`).

## Not included (add when needed)

WAF on the ALB/CloudFront, VPC flow logs, VPC endpoints (cut NAT traffic for ECR/S3/SSM),
Route 53 (DNS is provider-agnostic here), Redis, SQS, multi-region.
