# DevOps scaffold for `demo` (microservices-demo / `frontend`)

This scaffold was generated automatically on branch
`devops/scaffold-20260914193439`. It targets the `frontend` Go service in
this repo (built into a container named **demo**), deployed to **AWS EKS**
via **Amazon ECR**, for a single environment: **dev**.

> The upstream repo already ships its own Google-Cloud-oriented Dockerfiles,
> Skaffold config and Kubernetes manifests (per microservice, under
> `src/*/Dockerfile` and `kubernetes-manifests/`). Nothing there was
> overwritten. Everything generated here lives under new paths
> (`devops/`, `deploy/`, `.github/workflows/build-and-deploy.yml`) so it can
> coexist with the existing GCP-focused tooling.

## What was generated

| Path | Purpose |
|---|---|
| `devops/Dockerfile` | Multi-stage, distroless, non-root Dockerfile for the `frontend` Go binary (built as image `demo`). Build context is `src/frontend`. |
| `devops/.dockerignore` | Reference ignore file for that build context (existing `src/frontend/.dockerignore` was left untouched). |
| `.github/workflows/build-and-deploy.yml` | CI/CD: `go vet`/`go test` → build & push image to ECR → deploy to EKS `dev` namespace, gated by the `dev` GitHub Environment. Uses OIDC (`aws-actions/configure-aws-credentials`) — **no static AWS keys**. |
| `deploy/k8s/base/*.yaml` | Base Kubernetes manifests: Deployment (probes, resource limits, non-root securityContext), Service, ConfigMap, HPA, Ingress (AWS Load Balancer Controller / ALB annotations). |
| `deploy/k8s/overlays/dev/*` | Dev-environment kustomize overlay: dedicated `demo-dev` namespace, smaller resource requests, image tag substitution. |
| `deploy/infra/ecr/main.tf` | Terraform to create the `demo` ECR repository with image scanning on push and a lifecycle policy (expire untagged after 7 days, keep last 20 tagged). |
| `devops/README.md` | This file. |

## Required GitHub configuration

### Environments
Create a GitHub **Environment** named `dev` (Settings → Environments). Add
required reviewers/protection rules if you want manual approval before
deploys. The workflow's `deploy-dev` job runs under this environment.

### Secrets / Variables
No plaintext AWS credentials are used (OIDC/keyless auth). You must still
edit the workflow and manifests to replace these **placeholders** (search
for angle brackets):

| Placeholder | Where | Description |
|---|---|---|
| `<AWS_ACCOUNT_ID>` | workflow, `deploy/k8s/**`, Terraform usage | Your AWS account ID. |
| `<AWS_REGION>` | workflow (`env.AWS_REGION`), `deploy/k8s/**` | Target AWS region, e.g. `us-east-1`. |
| `<CLUSTER_NAME>` | workflow (`env.EKS_CLUSTER_NAME`) | Name of the target EKS cluster. |
| `<GITHUB_ACTIONS_ECR_ROLE_NAME>` | workflow | IAM role name (see below) assumable by GitHub Actions to push to ECR. |
| `<GITHUB_ACTIONS_EKS_ROLE_NAME>` | workflow | IAM role name assumable by GitHub Actions to deploy to EKS. |
| `<DEMO_DEV_HOSTNAME>` | `deploy/k8s/base/ingress.yaml` | DNS hostname to route to the dev Ingress (or remove the `host` field for a bare ALB DNS name). |
| `<ACM_CERTIFICATE_ARN>` | `deploy/k8s/base/ingress.yaml` (commented) | ACM cert ARN if/when you terminate TLS at the ALB. |
| `<TERRAFORM_STATE_BUCKET>` / `<TERRAFORM_LOCK_TABLE>` | `deploy/infra/ecr/main.tf` (commented) | Only needed if you enable the S3 remote backend. |

These can be committed directly (they are not secrets) or promoted to
repository/environment **Variables** if you prefer to keep them out of code —
in that case update the workflow to read `${{ vars.XYZ }}` instead.

## IAM / OIDC trust setup (manual, one-time, per AWS account)

1. **Create (or confirm) the GitHub OIDC identity provider** in IAM:
   `https://token.actions.githubusercontent.com`, audience
   `sts.amazonaws.com`.
2. **ECR push role** (`<GITHUB_ACTIONS_ECR_ROLE_NAME>`): trust policy scoped
   to this repo (`repo:duplocloud/microservices-demo:*`, or narrow to
   `ref:refs/heads/main`), with a permissions policy allowing
   `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`,
   `ecr:PutImage`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`,
   `ecr:CompleteLayerUpload`, `ecr:BatchGetImage` on the `demo` repository.
3. **EKS deploy role** (`<GITHUB_ACTIONS_EKS_ROLE_NAME>`): trust policy same
   as above, with permissions to call `eks:DescribeCluster` and be mapped
   in the cluster's `aws-auth` ConfigMap (or EKS access entries) to a
   Kubernetes RBAC role/rolebinding permitting `apply`/`get`/`rollout
   status` on Deployments/Services/ConfigMaps/HPAs/Ingresses in the
   `demo-dev` namespace.
4. **EKS cluster prerequisite**: the AWS Load Balancer Controller must
   already be installed in the cluster for the `Ingress` (class `alb`) to
   provision an ALB. This is a one-time cluster add-on, not something this
   scaffold installs.
5. **Terraform for ECR**: run manually (or via a separate pipeline) before
   the first image push:
   ```sh
   cd deploy/infra/ecr
   terraform init
   terraform apply -var="aws_region=<AWS_REGION>" -var="account_id=<AWS_ACCOUNT_ID>"
   ```

## Running the pipeline

1. Fill in all placeholders above.
2. Push to `main` touching `src/frontend/**` (or run the workflow manually
   via **Actions → Build and Deploy → Run workflow**).
3. The workflow will:
   - `go vet` and `go test` the frontend module,
   - build the image from `devops/Dockerfile` (context `src/frontend`) and
     push `\<ecr-registry\>/demo:<git-sha>` and `:latest` to ECR,
   - update the image tag in `deploy/k8s/overlays/dev` via `kustomize edit`,
   - `kubectl apply -k deploy/k8s/overlays/dev` against the `dev`
     environment/cluster, and wait for rollout.

## Assumptions & notes

- The repository contains 11 microservices; this scaffold only containerizes
  and deploys the **`frontend`** service as the "demo" application per the
  ticket description (single app name `demo`, single port `8000`). The
  frontend's default in-code port is 8080; it honors `PORT` env var, which
  is set to `8000` in both the Dockerfile and the ConfigMap to match the
  requested service port.
- The frontend depends on gRPC backends (`cartservice`, `productcatalogservice`,
  `currencyservice`, `checkoutservice`, `shippingservice`, `recommendationservice`,
  `adservice`) via env vars in `deploy/k8s/base/configmap.yaml`. Those
  services are **not** provisioned by this scaffold — wire the ConfigMap
  values to their in-cluster addresses once they're deployed, or the
  frontend pod will crash-loop (`mustMapEnv` panics on empty required env
  vars in `main.go`).
- No lint/test tooling beyond `go vet`/`go test` was assumed since no
  additional linter config (golangci-lint, etc.) was found in
  `src/frontend`.
- GHCR was not used (ECR was requested); no registry provisioning is needed
  beyond the Terraform in `deploy/infra/ecr`.
- Only the `dev` environment was requested, so no staging/prod overlay or
  environment-promotion gating was added beyond the single `dev` GitHub
  Environment gate already in the workflow.
