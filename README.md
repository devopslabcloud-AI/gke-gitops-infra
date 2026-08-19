# gke-gitops-infra

Infrastructure-as-Code and GitOps source of truth for the GKE project.

- `terraform/` — modular Terraform for a multi-zone GKE cluster (VPC, GKE, IAM, Workload Identity)
- `argocd/` — App-of-Apps root + AppProject
- `apps/` — microservice Kustomize base + prod overlay (image tag bumped by app-repo CI)
- `platform/` — ingress-nginx, cert-manager, kube-prometheus-stack, otel-collector, sealed-secrets (each an ArgoCD Application)
- `observability/` — Grafana dashboards + ServiceMonitors

ArgoCD reconciles this repo continuously with auto-sync, prune, and self-heal.
