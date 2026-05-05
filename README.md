# devops-challenges

Production-shaped reference deployment of a small containerised service to AWS:
**Go app → Docker → ECR → ECS Fargate behind an ALB → CloudWatch logs/metrics**, all
provisioned with modular Terraform and shipped by a GitHub Actions pipeline that
authenticates via OIDC (no static AWS keys in the repo).

The point of the project is the *plumbing*, not the app — the service is intentionally
trivial (three endpoints, standard library only) so the infrastructure, pipeline, and
operational hygiene are the things being demonstrated.

---

## Architecture

See [`docs/architecture.md`](docs/architecture.md) for the full Mermaid diagram. Short version:

- **VPC** with two public + two private subnets across two AZs, one NAT gateway.
- **ALB** (public subnets) terminates HTTP :80 and forwards to **ECS Fargate tasks**
  (private subnets, no public IP). Tasks may only be reached from the ALB security group.
- **ECR** holds the application image (immutable tags, scan-on-push, lifecycle keep-20).
- **CloudWatch** receives container logs, Container-Insights metrics, two alarms
  (service CPU, ALB 5xx), and a dashboard with logs + metrics widgets.
- **GitHub Actions** authenticates to AWS via an **OIDC** trust on a least-privilege
  IAM role. No long-lived access keys exist anywhere.

---

## Repository layout

```
app/                       Go service (stdlib only) + tests
Dockerfile                 Multi-stage build, distroless nonroot final image
terraform/
  modules/
    network/               VPC, subnets, IGW, NAT, route tables
    ecr/                   Repo + lifecycle policy
    alb/                   ALB, target group, security group, listener
    ecs/                   Cluster, task def, service, autoscaling, IAM
    observability/         Alarms + dashboard (log group lives at env layer)
  envs/dev/                Wires modules + GitHub OIDC role
.github/workflows/
  ci.yml                   Go test, terraform validate, Trivy scan
  cd.yml                   Build → ECR push → ECS deploy via OIDC
scripts/
  bootstrap-backend.sh     One-shot S3 backend bucket
  local-dev.sh             docker build + run locally
docs/architecture.md       Mermaid diagram + flow narrative
```

---

## Prerequisites

- AWS account with admin (or a role that can create VPC/IAM/ECS/ECR/CloudWatch).
- `aws` CLI v2, `terraform >= 1.6`, `docker`, `go >= 1.23`.
- A GitHub repo to push this code to.

---

## End-to-end deploy

> **Bootstrap order matters.** The CD workflow (`cd.yml`) triggers on every push
> to `main`, but it can only run after the GitHub secret `AWS_ROLE_TO_ASSUME` is
> set. That value is produced by `terraform apply` (output:
> `github_actions_role_arn`). So the very first push to a fresh repo will see
> the CD job fail with a missing-secret error — that is expected. Run the steps
> below once, paste the role ARN into repo *Settings → Secrets and variables →
> Actions → New repository secret* as `AWS_ROLE_TO_ASSUME`, then either push a
> new commit or re-run the failed `cd` workflow from the Actions tab.

### 1. Bootstrap the Terraform backend (once per account)

```bash
scripts/bootstrap-backend.sh my-tfstate-bucket us-east-1
```

Creates an S3 bucket with versioning, SSE, and public-access blocked. State locking
uses S3 native lockfiles (Terraform ≥ 1.10) — no DynamoDB table needed.

### 2. Configure & init

```bash
cd terraform/envs/dev
cp backend.hcl.example backend.hcl       # set bucket = "my-tfstate-bucket"
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set github_repository = "your-org/your-repo"

terraform init -backend-config=backend.hcl
```

### 3. First apply (placeholder image)

```bash
terraform apply
```

The first apply uses `public.ecr.aws/nginx/nginx:stable-alpine` as a placeholder so ECS
can start. Outputs include:

- `alb_url` — public URL.
- `github_actions_role_arn` — paste this into your GitHub repo as a secret named
  `AWS_ROLE_TO_ASSUME`.

### 4. Push the code to GitHub

`cd.yml` triggers on push to `main`:

1. Assumes `AWS_ROLE_TO_ASSUME` via OIDC.
2. Builds the image with `APP_VERSION=<sha>` baked in.
3. Pushes to ECR.
4. Re-renders the task definition with the new image and forces a deployment.
5. Waits for service stability; ECS circuit breaker auto-rolls back on failure.

### 5. Verify

```bash
curl "$(terraform output -raw alb_url)/"
curl "$(terraform output -raw alb_url)/health"
```

The `/` response includes `version` (= short SHA) and `git_sha`, so you can confirm
which build is live. CloudWatch dashboard name is in the `dashboard_name` output.

### 6. Tear down

```bash
terraform destroy
```

ECR has `force_delete = true` in `dev`, so the destroy doesn't get stuck on remaining
images. (For prod, flip that off.)

---

## Local development

```bash
scripts/local-dev.sh           # docker build + run on :8000
# or:
cd app && go test ./...
cd app && go run .
```

---

## Design decisions

| Decision | Rationale |
|---|---|
| **ECS Fargate, not EC2/EKS** | No node fleet to patch, no control plane to budget for, fastest path to a running service. EKS would be over-engineered for a single workload; EC2 would mean owning AMI lifecycle and SSM agents. |
| **Go stdlib service** | Tiny static binary → distroless runtime image (~10 MB). Fewer deps = smaller attack surface = honest demo of supply-chain hygiene. |
| **Distroless `nonroot` base** | No shell, no package manager, runs as UID 65532. ECS task config also uses `readonlyRootFilesystem`. |
| **GitHub Actions over Jenkins** | The brief preferred Jenkins, but Jenkins needs somewhere to run (another EC2 + AMI patching + plugin maintenance). GHA + OIDC removes long-lived AWS keys *and* removes a server to operate — better security and operational story for the same outcome. Jenkins would be the right call if the broader org already runs it. |
| **OIDC, not access keys** | Static keys in CI are the most common cloud breach vector. OIDC issues short-lived STS credentials per workflow run; the trust policy is scoped to one repo. |
| **Modular Terraform** | Each module owns one concern. Adding `staging/` or `prod/` is copy `envs/dev/` and adjust variables — no module changes. |
| **S3 native lockfiles** | Terraform 1.10+ removes the need for the DynamoDB table dance. One fewer resource to bootstrap. |
| **Two alarms, not twenty** | CPU + ALB 5xx are signals an on-call would actually act on. The CloudWatch dashboard surfaces the rest visually. Alarm noise is a real-world failure mode. |
| **Single NAT gateway** | Cost-conscious for a demo (~$32/mo vs $96/mo for one-per-AZ). Trade-off: NAT-AZ outage breaks egress. Documented as an upgrade. |
| **`ignore_changes` on task def** | The CD pipeline owns image rollouts; Terraform owns infra shape. Without this, every `apply` would fight every deploy. |

---

## Assumptions

- A reviewer is going to apply, browse the URL, and destroy — so defaults favour
  cost and ergonomics over hardening (`force_delete` on ECR, single NAT, `*` for the
  OIDC `sub` claim instead of `refs/heads/main`).
- The reviewer has admin in a sandbox AWS account.
- "Basic monitoring/logging" means structured app logs in CloudWatch + a small
  number of meaningful alarms — not a full SLO/SLI rollout.

## Limitations / next steps

These are deliberate cuts, not oversights:

- **No HTTPS / ACM** — needs a real domain. Add `aws_acm_certificate` + a 443
  listener + HTTP→HTTPS redirect.
- **No WAF** — `aws_wafv2_web_acl` with managed rule groups in front of the ALB.
- **One NAT gateway** — duplicate per AZ for prod.
- **OIDC trust scoped to whole repo** — tighten to `refs/heads/main` for prod.
- **No secrets demo** — task role is empty; SSM Parameter Store or Secrets Manager
  would plug in via the task definition `secrets` block.
- **No staging environment** — `envs/staging/` would mirror `envs/dev/` with
  different sizing and a stricter OIDC trust.
- **No SLO alarms** — p99 latency and target-group unhealthy-host alarms are the
  obvious next two to add.
- **Single region** — multi-region active/passive needs Route53 + replicated state.

---

## Security posture (what this repo gets right)

- No long-lived AWS credentials in CI; OIDC with a per-repo IAM role.
- IAM policies for the deployer role are scoped to the specific ECR repo and ECS
  service it manages (`PassRole` is conditioned on `ecs-tasks.amazonaws.com`).
- Tasks run in private subnets only; the ALB SG is the only inbound source on the
  task SG.
- ECR repo: `IMMUTABLE` tags + scan-on-push.
- Container: distroless, nonroot, `readonlyRootFilesystem`.
- ALB drops invalid header fields.
- Terraform state bucket: versioned, encrypted, public access blocked.
- CI fails on HIGH/CRITICAL Trivy findings with a known fix.
