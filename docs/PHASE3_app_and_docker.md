# Phase 3 — Go Microservice & Dockerization

## Concepts first (plain English)

**Why Go for this.** Go compiles to a single static binary with no runtime/interpreter, so the container can be tiny and start in milliseconds — exactly what Kubernetes wants when it scales pods up and down.

**The three probe endpoints.** Kubernetes constantly asks your pod two questions:
- `/healthz` (**liveness**) — "Are you alive?" If this fails, K8s *restarts* the pod.
- `/readyz` (**readiness**) — "Can you take traffic *right now*?" If this fails, K8s keeps the pod running but *removes it from the load balancer* until it recovers. We return 503 during a 2-second warmup and again during shutdown, so no request is ever sent to a pod that can't serve it.
- `/metrics` — the door Prometheus knocks on to read our numbers.

**Custom Prometheus metrics = the Golden Signals.** We expose three collectors that map to the classic SRE signals:
- `http_requests_total` (a *counter*, labelled by status) → **Traffic** and **Errors**.
- `http_request_duration_seconds` (a *histogram*) → **Latency** (Grafana computes p50/p95/p99 from it).
- `http_in_flight_requests` (a *gauge*) → **Saturation** (how busy we are right now).

We label metrics by the route **pattern** (`/api/v1/items/{id}`) not the raw path (`/api/v1/items/42`, `/api/v1/items/43`, …). Using raw paths would create millions of unique label combinations and melt Prometheus — that mistake is called *high cardinality*.

**Structured JSON logs to stdout.** We never write log files. We print JSON lines to stdout and let the platform collect them. JSON means the fields (status, route, duration) are queryable, not just free text. This is the "12-factor app" logging model.

**OpenTelemetry (OTel).** A vendor-neutral standard for traces/metrics. Our app sends traces over OTLP to a Collector (Phase 6). It's wired to be optional — off unless `OTEL_EXPORTER_OTLP_ENDPOINT` is set — so the app also runs fine on your laptop.

**Graceful shutdown.** On `SIGTERM` (which K8s sends before killing a pod) we flip readiness to false, let the load balancer drain us, then finish in-flight requests before exiting. This is what makes rolling deploys **zero-downtime**.

**Multi-stage, non-root, distroless Dockerfile.** Two stages: a heavy `golang` image *builds* the binary, then we copy just that binary into `gcr.io/distroless/static:nonroot` — an image with no shell, no package manager, and a non-root user (UID 65532). Result: an image a few MB in size with almost no attack surface (nothing for an attacker to exploit, no shell to break into).

---

## Files written (`gke-microservice-app`)

```
cmd/server/main.go              # wiring: router, probes, metrics, OTel, graceful shutdown
internal/handlers/health.go     # /healthz + /readyz
internal/handlers/api.go        # GET / and GET /api/v1/items/{id}
internal/metrics/metrics.go     # the 3 custom Prometheus collectors
internal/middleware/observability.go  # per-request metrics + JSON log
internal/telemetry/otel.go      # OTLP tracer provider
build/Dockerfile                # multi-stage distroless non-root
.golangci.yml .dockerignore .trivyignore go.mod
```

> Module path is `github.com/example/gke-microservice-app`. Replace `example` with your GitHub username in `go.mod` **and** the import lines (one `sed` does it — see commands).

---

## Exact commands (run locally)

```bash
cd gke-microservice-app

# 0. (Optional) rename the module to your GitHub owner
export GH_OWNER="my-github-username"
grep -rl 'github.com/example/gke-microservice-app' . \
  | xargs sed -i '' "s#github.com/example/gke-microservice-app#github.com/${GH_OWNER}/gke-microservice-app#g"
# (on Linux use: sed -i "s#...#...#g" instead of sed -i '')

# 1. Resolve dependencies and CREATE go.sum (required before docker build)
go mod tidy

# 2. Static checks
go vet ./...
# golangci-lint if installed:
# golangci-lint run

# 3. Run it locally
go run ./cmd/server
# in another terminal:
curl -s localhost:8080/ | jq
curl -s localhost:8080/healthz
curl -s localhost:8080/readyz          # 503 for first 2s, then 200
curl -s localhost:8080/api/v1/items/42 | jq
curl -s localhost:8080/metrics | grep http_requests_total

# 4. Build the container (multi-stage)
docker build -f build/Dockerfile -t gke-microservice:local .

# 5. Run the container and confirm the image is tiny + non-root
docker run --rm -p 8080:8080 gke-microservice:local &
docker images gke-microservice:local        # expect single-digit MB
curl -s localhost:8080/metrics | head
```

---

## Gotchas

- **`docker build` fails at `COPY go.mod go.sum`** → you skipped `go mod tidy`; run it first so `go.sum` exists.
- **`/readyz` returns 503** → that's expected for the first 2 seconds (warmup). It's intentional to prove readiness works.
- **Traces don't appear** → the app only exports traces when `OTEL_EXPORTER_OTLP_ENDPOINT` is set; on a laptop with no collector it stays quiet by design.

---

## Interview Questions & Answers (Phase 3)

**Q1. What's the difference between liveness and readiness probes, and why do you need both?**
> Liveness answers "is the process alive?" — if it fails, Kubernetes restarts the pod. Readiness answers "can it serve traffic right now?" — if it fails, Kubernetes leaves the pod running but pulls it out of the Service's load-balancer pool. You need both because a pod can be alive but temporarily unable to serve — during warmup, a dependency blip, or graceful shutdown. In my service `/readyz` returns 503 during a startup warmup and again on SIGTERM, so the load balancer drains the pod before it stops. That's what makes rolling deployments zero-downtime.

**Q2. How did you instrument the service, and how do you avoid a Prometheus cardinality explosion?**
> I expose three custom collectors that map to the golden signals — a counter for traffic/errors, a histogram for latency, and a gauge for in-flight requests — all updated in one middleware. The key discipline is labelling by the route *pattern* like `/api/v1/items/{id}` rather than the raw URL. If I labelled by raw path, every unique ID would create a new time series and overwhelm Prometheus. Using the pattern keeps the label set small and bounded.

**Q3. Walk me through your Dockerfile and why it's production-hardened.**
> It's multi-stage. The first stage uses the full Go image to compile a static, stripped binary with CGO disabled. The second stage is `distroless/static:nonroot` — no shell, no package manager, and it runs as a non-root user. I copy only the binary in, so the final image is a few megabytes with almost no attack surface: there's nothing for an attacker to pivot into and no root user to escalate to. Smaller images also pull and start faster, which matters when the autoscaler is spinning up pods.

---

*Next: Phase 4 — the GitHub Actions CI pipeline (lint → test → Trivy → multi-arch build → push to Artifact Registry → commit the new image tag into the GitOps repo).*
