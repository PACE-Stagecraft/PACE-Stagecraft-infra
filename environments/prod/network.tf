# ── Networking ───────────────────────────────────────────────────────
# VPC with public / private / database subnets across 3 AZs, per-AZ NAT
# (prod HA). Also the Bedrock interface VPC endpoints (see note below).

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr

  azs              = local.azs
  private_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets   = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]
  database_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k + 8)]

  create_database_subnet_group = true

  enable_nat_gateway   = true
  single_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

# NOTE: These Bedrock VPC endpoints assume same-account Bedrock. The dev
# environment moved to cross-account Bedrock (sts:AssumeRole into the company
# account) and removed these. If prod also uses cross-account Bedrock, delete
# this block — cross-account traffic goes over the public Bedrock endpoint.
resource "aws_security_group" "bedrock_vpce" {
  name        = "${local.name}-bedrock-vpce"
  description = "Allow HTTPS from within the VPC to Bedrock interface endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
}

resource "aws_vpc_endpoint" "bedrock" {
  for_each = toset(["bedrock", "bedrock-runtime", "bedrock-agent-runtime"])

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.bedrock_vpce.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name}-${each.key}-vpce"
  }
}
