# Phase 1 — Architecture & Repository Structure

**Project:** Enterprise GitOps Deployment & Observability Pipeline on GKE
**Topology:** Polyrepo — `gke-microservice-app` (app + CI) and `gke-gitops-infra` (IaC + GitOps manifests)
**Domain strategy:** `app.<GKE_LB_IP>.sslip.io` (parameterized), Let's Encrypt HTTP-01 via NGINX Ingress.

---

## 1.1 System context (C4 level 1)

```mermaid
flowchart LR
    dev([Developer])
    user([End User])

    subgraph GH[GitHub]
      appRepo[(gke-microservice-app)]
      gitopsRepo[(gke-gitops-infra)]
    end

    subgraph GCP[Google Cloud]
      AR[(Artifact Registry)]
      subgraph GKE[GKE Multi-Zone Cluster]
        argo[ArgoCD]
        svc[Go Microservice]
        obs[Prometheus / Grafana / OTel]
      end
    end

    dev -->|git push code| appRepo
    appRepo -->|CI: build, scan, push| AR
    appRepo -->|CI: commit new image tag| gitopsRepo
    argo -->|pull desired state| gitopsRepo
    argo -->|apply / self-heal| svc
    argo -->|apply| obs
    svc -->|pull image| AR
    user -->|HTTPS| svc
    svc -.->|scrape / OTLP| obs
```

---

## 1.2 End-to-end traffic flow (request path)

```mermaid
flowchart TB
    client([Client / Browser])
    dns[["app.&lt;LB_IP&gt;.sslip.io<br/>(sslip.io wildcard DNS)"]]
    lb[GCP L4 LoadBalancer<br/>External IP]
    nginx[NGINX Ingress Controller]
    cm[Cert-Manager<br/>Lets Encrypt HTTP-01]
    svc[Service ClusterIP :80]
    pods[Go Microservice Pods<br/>HPA 2..10]

    client -->|TLS 443| dns --> lb --> nginx
    cm -. issues/renews TLS cert .-> nginx
    nginx -->|/ route, TLS terminated| svc --> pods
    pods -->|/metrics :9090| prom[Prometheus]
    pods -->|OTLP traces/metrics| otel[OTel Collector]
    otel --> prom
    prom --> graf[Grafana]
```

The `.sslip.io` host resolves any `app.<IP>.sslip.io` name to `<IP>` with no DNS setup, so TLS + Ingress work the moment the LoadBalancer IP is assigned. Swap in a custom domain later by changing one Helm/Kustomize variable.

---

## 1.3 CI pipeline (in `gke-microservice-app`)

```mermaid
flowchart LR
    push([push / tag on main]) --> lint[golangci-lint + go vet]
    lint --> test[go test ./...]
    test --> scanfs[Trivy FS + config scan]
    scanfs --> build[Docker Buildx<br/>linux/amd64 + arm64]
    build --> scanimg[Trivy image scan<br/>fail on HIGH/CRITICAL]
    scanimg --> push2[Push to Artifact Registry<br/>tag = git SHA + semver]
    push2 --> bump[Checkout gke-gitops-infra<br/>update image tag<br/>commit + push]
    bump --> done([ArgoCD detects change])
```

Authentication to GCP uses **Workload Identity Federation** (keyless OIDC) — no long-lived JSON service-account keys in GitHub secrets. The cross-repo tag bump uses a scoped deploy token / GitHub App installation token.

---

## 1.4 GitOps sync & self-healing loop (ArgoCD)

```mermaid
flowchart TB
    subgraph gitops[gke-gitops-infra]
      root[root-app.yaml<br/>App-of-Apps]
      childApps[Child Applications:<br/>platform + microservice + observability]
    end

    subgraph cluster[GKE Cluster]
      argocd[ArgoCD app-controller]
      live[Live cluster state]
    end

    root --> childApps
    argocd -->|1 - poll every 3m / webhook| gitops
    argocd -->|2 - diff desired vs live| live
    live -->|3 - drift detected| argocd
    argocd -->|4 - auto-sync + prune + selfHeal| live
    argocd -->|5 - report Synced / Healthy| root
```

**App-of-Apps:** a single `root-app` Application points at a directory of child `Application` manifests. Bootstrapping the root app deploys the entire platform. Each child has `syncPolicy.automated` with `prune: true` and `selfHeal: true`, so any manual `kubectl edit` drift is reverted automatically.

---

## 1.5 Repository structure

### App repo — `gke-microservice-app`

```
gke-microservice-app/
├── cmd/
│   └── server/
│       └── main.go               # entrypoint, graceful shutdown, wiring
├── internal/
│   ├── handlers/
│   │   ├── api.go                # REST business endpoints
│   │   └── health.go             # /healthz, /readyz
│   ├── metrics/
│   │   └── metrics.go            # custom Prometheus collectors
│   ├── middleware/
│   │   └── observability.go      # request logging + RED metrics
│   └── telemetry/
│       └── otel.go               # OpenTelemetry tracer/meter provider
├── build/
│   └── Dockerfile                # multi-stage, distroless, non-root
├── deploy/
│   └── README.md                 # pointer to gitops repo (no manifests here)
├── .github/
│   └── workflows/
│       └── ci-cd.yaml            # lint→test→scan→build→push→tag-bump
├── go.mod
├── go.sum
├── .golangci.yml
├── .dockerignore
├── .trivyignore
└── README.md
```

### GitOps / Infra repo — `gke-gitops-infra`

```
gke-gitops-infra/
├── terraform/
│   ├── modules/
│   │   ├── vpc/                  # network, subnets, secondary ranges, NAT
│   │   ├── gke/                  # cluster + node pools + workload identity
│   │   └── iam/                  # service accounts + WI + WIF for CI
│   └── envs/
│       └── prod/
│           ├── main.tf           # composes modules
│           ├── variables.tf
│           ├── vpc.tf
│           ├── gke.tf
│           ├── iam.tf
│           ├── outputs.tf
│           ├── versions.tf       # providers + backend
│           └── terraform.tfvars.example
├── argocd/
│   ├── bootstrap/
│   │   └── root-app.yaml         # App-of-Apps root
│   └── projects/
│       └── platform-project.yaml # AppProject RBAC/allowlists
├── apps/
│   └── microservice/
│       ├── base/                 # deployment, service, ingress, hpa, kustomization
│       └── overlays/prod/        # env-specific patches + image tag
├── platform/
│   ├── ingress-nginx/            # ArgoCD App -> Helm chart + values
│   ├── cert-manager/             # ArgoCD App + ClusterIssuer
│   ├── kube-prometheus-stack/    # ArgoCD App + Helm values
│   ├── opentelemetry-collector/  # ArgoCD App + Helm values
│   └── sealed-secrets/           # ArgoCD App (secret mgmt)
├── observability/
│   ├── dashboards/               # Grafana Golden Signals JSON (as ConfigMap)
│   └── servicemonitors/          # ServiceMonitor CRDs
├── docs/
│   └── PHASE1_architecture.md
└── README.md
```

**Separation of concerns:** the app repo never contains Kubernetes manifests — its only tie to the cluster is the CI job that bumps the image tag in `apps/microservice/overlays/prod`. The GitOps repo is the single source of truth ArgoCD reconciles against.

---

## 1.6 Tech stack summary

| Layer | Choice |
|---|---|
| IaC | Terraform (modular), GCS remote state |
| Cluster | GKE, multi-zone, managed node pool + autoscaling, Workload Identity |
| App | Go — chi router, `promhttp`, OpenTelemetry SDK, `slog` JSON logs |
| Container | Multi-stage build → distroless static, non-root UID |
| CI | GitHub Actions + Workload Identity Federation, Trivy, Buildx multi-arch |
| Registry | GCP Artifact Registry |
| CD / GitOps | ArgoCD App-of-Apps, auto-sync + prune + self-heal |
| Ingress/TLS | NGINX Ingress + Cert-Manager (Let's Encrypt HTTP-01) |
| Observability | kube-prometheus-stack (Prometheus + Grafana + Alertmanager), OTel Collector |
| Secrets | Sealed Secrets (with GCP Secret Manager note) |

---

*Next: Phase 2 — modular Terraform for the GKE cluster (VPC, node pools, IAM, Workload Identity).*
