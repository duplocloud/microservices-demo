# syntax=docker/dockerfile:1.7
#
# Production Dockerfile for the "demo" application (Online Boutique `frontend` service).
# Build context MUST be `src/frontend` (see .github/workflows/build-and-deploy.yml).
#
#   docker build -f devops/Dockerfile src/frontend
#
# ---- Build stage ----------------------------------------------------------
ARG GO_VERSION=1.25
FROM golang:${GO_VERSION}-alpine AS builder

WORKDIR /src

# Cache dependency downloads separately from source so code changes don't
# invalidate the module cache.
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/root/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go mod download

COPY . .

# Static, stripped binary - no CGO, so it runs on distroless/scratch.
RUN --mount=type=cache,target=/root/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" -o /out/demo .

# ---- Runtime stage ----------------------------------------------------------
# distroless "nonroot" image: no shell, no package manager, runs as uid 65532.
FROM gcr.io/distroless/static-debian12:nonroot AS runtime

WORKDIR /app

COPY --from=builder --chown=nonroot:nonroot /out/demo /app/demo
COPY --from=builder --chown=nonroot:nonroot /src/templates /app/templates
COPY --from=builder --chown=nonroot:nonroot /src/static /app/static

# Application listens on $PORT (defaults to 8080 in-code); we pin it to the
# service port requested for this deployment.
ENV PORT=8000
ENV GOTRACEBACK=single

USER nonroot:nonroot

EXPOSE 8000

# distroless images ship no shell/curl/wget, so a Docker HEALTHCHECK cannot
# exec a probe command here. Container health is instead verified via the
# Kubernetes liveness/readiness probes defined in deploy/k8s (HTTP GET
# /_healthz on the service port).

ENTRYPOINT ["/app/demo"]
