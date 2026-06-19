# agora-infra

Terraform infrastructure for aGorA on AWS EKS. Uses [terraform-aws-modules](https://github.com/terraform-aws-modules) from the public registry — custom modules only for SQS policy bindings, IRSA role setup, and Secrets Manager entries.

**Part of**: [aGora-Ops](https://github.com/aGora-Ops)

## Architecture

| Component | Module | Notes |
|-----------|--------|-------|
| VPC | `terraform-aws-modules/vpc/aws ~> 5.8` | 3 AZs, private/public subnets |
| EKS | `terraform-aws-modules/eks/aws ~> 20.11` | Managed node groups, IRSA, add-ons |
| RDS | `terraform-aws-modules/rds/aws ~> 6.7` | Postgres 15, password from `random_password` |
| ElastiCache | `terraform-aws-modules/elasticache/aws ~> 1.2` | Redis 7, encryption at rest + transit |
| ECR | `terraform-aws-modules/ecr/aws ~> 2.2` | 4 repos, immutable tags |
| SQS | `modules/sqs/` (custom) | DLQ + CloudWatch alarm, KMS encryption, IAM queue policy |
| IAM / IRSA | `modules/iam/` (custom) | Pod identity bindings for api/webhook/worker/external-secrets |
| Secrets Manager | `modules/secrets/` (custom) | One secret per service per environment — see below |
| External Secrets Operator | `helm_release` + `kubernetes_manifest` | Syncs Secrets Manager → k8s Secrets |
| ArgoCD | `helm_release` + `kubernetes_manifest` (Application) | Watches `agora-helm`, auto-deploys on every commit |
| WAF | `aws_wafv2_web_acl` | AWS managed rule set |
| ACM + Route53 | `terraform-aws-modules/acm/aws ~> 4.3` | Optional — set `domain_name` in tfvars |
| SNS | `aws_sns_topic` | Email alert on DLQ depth > 0 |

## How secrets actually get to a running pod

```
terraform apply
  → module.secrets creates agora/{env}/{service} in Secrets Manager
  → helm_release.external_secrets installs ESO with an IRSA role scoped to
    secretsmanager:GetSecretValue on arn:...:secret:agora/*
  → kubernetes_manifest.cluster_secret_store registers that role with ESO
  → each Helm chart's templates/externalsecret.yaml (in agora-helm) creates
    an ExternalSecret CR pointing at agora/{env}/{service}
  → ESO syncs it into a native k8s Secret
  → the Deployment's envFrom: secretRef reads it
```

No `aws secretsmanager create-secret` CLI step needed — `terraform apply` creates everything. No `helm --set secrets.X=...` either — secrets never touch CI logs.

**SECRET_KEY is shared between `api` and `worker`** (`random_password.secret_key`, generated once) — it signs JWTs in api and derives the Fernet token-encryption key in both. If you ever rotate it, rotate both secrets together or token decryption breaks.

## How a deploy actually happens (GitOps)

```
git push to a service repo (main branch)
  → ci.yml: build, scan, push to ECR, helm-update commits new
    image.repository + image.tag to agora-helm
  → ArgoCD (watching agora-helm, installed by this repo) detects the commit
  → ArgoCD syncs the chart to the agora namespace automatically
```

ArgoCD needs read access to `agora-helm` (private repo) — set `argocd_repo_pat` to a GitHub PAT with at least read access to that repo.

## Bootstrap (first time only)

```bash
# Create S3 state bucket and DynamoDB lock table
aws s3 mb s3://agora-terraform-state --region us-east-1
aws dynamodb create-table \
  --table-name agora-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

## Usage

```bash
cd environments/dev
terraform init

# Supply secrets via env vars — never put real values in terraform.tfvars
export TF_VAR_github_client_id="..."
export TF_VAR_github_client_secret="..."
export TF_VAR_github_webhook_secret="$(openssl rand -hex 32)"
export TF_VAR_alert_email="you@example.com"
export TF_VAR_argocd_repo_pat="ghp_..."

terraform plan
terraform apply
```

## Dev vs Prod differences

| Setting | Dev | Prod |
|---------|-----|------|
| NAT Gateways | Single | Per-AZ |
| EKS public endpoint | Yes | No (private only) |
| Node count | 2 app + 1 worker | 3 app + 2 worker |
| RDS Multi-AZ | No | Yes |
| Redis replicas | 1 | 2 (primary + replica) |
| Deletion protection | Off | On |

## Known follow-ups (not yet automated)

- `terraform validate`/`plan` has never been run against a real AWS account — expect to fix provider-version or argument mismatches on first real apply
- DB password rotation: `random_password.db_password` is static once applied; rotating it means a coordinated `terraform apply` + pod restart, not yet scripted
- ArgoCD's own admin UI access (port-forward or ingress) isn't wired up — `kubectl port-forward svc/argocd-server -n argocd 8080:443` for now
