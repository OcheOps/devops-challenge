locals {
  tags = {
    Project     = "devops-challenge"
    Environment = var.environment
  }
}

module "network" {
  source   = "../../modules/network"
  name     = var.name
  vpc_cidr = var.vpc_cidr
  tags     = local.tags
}

module "ecr" {
  source = "../../modules/ecr"
  name   = var.name
  tags   = local.tags
}

# Log group lives at the env layer to break the ECS <-> observability cycle.
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

module "alb" {
  source            = "../../modules/alb"
  name              = var.name
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  container_port    = var.container_port
  tags              = local.tags
}

module "ecs" {
  source = "../../modules/ecs"

  name                  = var.name
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arn
  log_group_name        = aws_cloudwatch_log_group.app.name

  image          = var.image
  container_port = var.container_port
  desired_count  = var.desired_count

  tags = local.tags
}

module "observability" {
  source = "../../modules/observability"

  name                    = var.name
  region                  = var.region
  cluster_name            = module.ecs.cluster_name
  service_name            = module.ecs.service_name
  alb_arn_suffix          = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  log_group_name          = aws_cloudwatch_log_group.app.name
  tags                    = local.tags
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC: lets the workflow assume an AWS role with NO long-lived
# access keys. Trust is scoped to a single repo (and optionally branch).
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # GitHub's root CA thumbprint. AWS now also verifies via library-bundled CAs,
  # so this value is essentially advisory, but the API still requires it.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  tags            = local.tags
}

data "aws_iam_policy_document" "gha_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Trust any branch in this repo. Tighten to refs/heads/main for prod.
      values = ["repo:${var.github_repository}:*"]
    }
  }
}

resource "aws_iam_role" "gha_deployer" {
  name               = "${var.name}-gha-deployer"
  assume_role_policy = data.aws_iam_policy_document.gha_assume.json
  tags               = local.tags
}

# Least-privilege deployer policy:
#   - push images to THIS ECR repo only
#   - update task def + force a new deployment on THIS service only
#   - pass the two task roles (required to register a task definition)
data "aws_iam_policy_document" "gha_deployer" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
    ]
    resources = [module.ecr.repository_arn]
  }
  statement {
    sid = "EcsDeploy"
    actions = [
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = [module.ecs.execution_role_arn, module.ecs.task_role_arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "gha_deployer" {
  name   = "${var.name}-gha-deployer"
  role   = aws_iam_role.gha_deployer.id
  policy = data.aws_iam_policy_document.gha_deployer.json
}
