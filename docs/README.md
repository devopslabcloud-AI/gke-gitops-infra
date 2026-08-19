# Project Docs — Enterprise GitOps on GKE

Phase-by-phase guides (concepts → commands → interview Q&A):

1. [Phase 1 — Architecture & repo structure](PHASE1_architecture.md)
2. [Phase 2 — Terraform IaC for GKE](PHASE2_terraform.md)
3. [Phase 3 — Go microservice & Dockerfile](PHASE3_app_and_docker.md)
4. [Phase 4 — GitHub Actions CI](PHASE4_ci_pipeline.md)
5. [Phase 5 — ArgoCD App-of-Apps](PHASE5_argocd_gitops.md)
6. [Phase 6 — Observability stack](PHASE6_observability.md)
7. [Phase 7 — Validation, chaos & drift](PHASE7_validation_chaos_drift.md)

## End-to-end execution order (the happy path)

```
# 1. Provision infra
cd terraform/envs/prod && terraform init && terraform apply
gcloud container clusters get-credentials gitops-gke --region us-central1

# 2. Wire CI (app repo): set GCP_* variables + GITOPS_TOKEN, then push app repo

# 3. Install ArgoCD + bootstrap everything
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# replace REPLACE_OWNER / PROJECT_ID placeholders, commit, then:
kubectl apply -f argocd/projects/platform-project.yaml
kubectl apply -f argocd/bootstrap/root-app.yaml

# 4. Grab the NGINX LoadBalancer IP -> set the sslip.io host -> commit
# 5. Verify: argocd apps Synced/Healthy, https app reachable with valid TLS
# 6. Chaos/drift demo: scripts/chaos-drift-test.sh
# 7. terraform destroy when done
```

Placeholders to replace before applying: `REPLACE_OWNER` (GitHub owner), `PROJECT_ID` (GCP project), `REPLACE_LB_IP` (set from the NGINX LB IP), and the tfstate bucket name in `terraform/envs/prod/versions.tf`.
