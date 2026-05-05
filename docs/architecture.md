# Architecture

```mermaid
flowchart LR
    Dev[Developer push to main] --> GH[GitHub Actions]

    subgraph CI["CI (every PR & push)"]
      GH --> GoTest["go vet / test / build"]
      GH --> TFV["terraform fmt + validate"]
      GH --> Trivy["docker build + Trivy scan"]
    end

    GH -- "OIDC AssumeRole" --> AWS

    subgraph AWS["AWS Account (us-east-1)"]
      direction TB
      ECR[(ECR repo<br/>scan-on-push)]
      GH -- "docker push :sha" --> ECR

      subgraph VPC["VPC 10.40.0.0/16"]
        direction TB
        IGW[Internet Gateway]
        ALB["ALB :80<br/>SG: 0.0.0.0/0"]
        NAT[NAT Gateway]

        subgraph PUB["Public subnets (2 AZs)"]
          ALB
          NAT
        end

        subgraph PRV["Private subnets (2 AZs)"]
          T1["Fargate task 1<br/>distroless, nonroot"]
          T2["Fargate task 2"]
        end

        ALB --> T1
        ALB --> T2
        T1 --> NAT
        T2 --> NAT
        NAT --> IGW
      end

      ECR -.image pull.-> T1
      ECR -.image pull.-> T2

      T1 --> CWLogs[(CloudWatch Logs<br/>/ecs/devops-challenge-dev)]
      T2 --> CWLogs

      CWMetrics[CloudWatch Metrics + Alarms<br/>CPU, ALB 5xx]
      Dash[CloudWatch Dashboard]
      CWLogs --- Dash
      CWMetrics --- Dash
    end

    User[Internet user] --> ALB
```

## Request flow

1. Client hits `http://<alb-dns>/` on port 80.
2. ALB terminates the connection and forwards to a healthy Fargate task in a private subnet (target type `ip`, awsvpc networking).
3. The Go service responds. stdout is captured by the `awslogs` driver and shipped to the `/ecs/<name>` log group.
4. CloudWatch Container Insights collects per-task CPU/memory; ALB emits request and 5xx counters.

## Deploy flow

1. PR opens → `ci.yml` runs (Go tests, `terraform validate`, Trivy scan). No AWS access.
2. Merge to `main` → `cd.yml` runs:
   - Assumes `gha_deployer` role via OIDC.
   - Builds image tagged with the short SHA, pushes to ECR.
   - Pulls the live task definition, replaces the image, registers a new revision.
   - Calls `UpdateService` and waits for stability. Circuit breaker auto-rolls back on failure.
