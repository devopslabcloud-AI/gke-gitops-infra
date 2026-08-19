# Phase 4 — CI Pipeline (GitHub Actions)

## Concepts first (plain English)

**CI vs CD, and why they're split here.** *CI (Continuous Integration)* lives in the **app repo** and does everything up to producing a trusted image: lint, test, scan, build, push. *CD (Continuous Delivery)* is handled by **ArgoCD** (Phase 5) from the **GitOps repo**. The only bridge between them is the last CI job, which commits the new image tag into the GitOps repo. This is the heart of GitOps: **CI never touches the cluster** — it just changes Git, and the cluster converges to Git.

**Why keyless auth (Workload Identity Federation).** The old way to let GitHub push to GCP was to paste a service-account JSON key into GitHub secrets — a long-lived credential that's a top cause of breaches. Instead, GitHub gives GCP a short-lived OIDC token that proves "I'm the workflow for repo X," and GCP (via the WIF pool we built in Phase 2) trusts it. `permissions: id-token: write` is what lets the workflow request that token.

**The pipeline stages (each gates the next):**
1. **test** — `go vet`, `golangci-lint`, `go test -race`. Catches bugs and style issues.
2. **security-scan** — Trivy scans the source/deps for known CVEs; fails the build on HIGH/CRITICAL. "Shift-left security."
3. **build-push** — `docker buildx` builds for **both** `amd64` and `arm64` (multi-arch), pushes to Artifact Registry, then Trivy scans the *built image* too.
4. **bump-gitops** — checks out the GitOps repo and runs `kustomize edit set image` to write the new tag, then commits. ArgoCD sees the commit and deploys.

**Image tag strategy.** We tag with `sha-<short-commit>` (immutable, traceable to exact code) plus `latest`. GitOps always pins the SHA tag so every deploy is reproducible — you can look at Git and know exactly which image is running.

**Multi-arch (why bother).** Building for arm64 as well as amd64 means the same image runs on Graviton/Ampere ARM nodes (cheaper) and Apple-silicon laptops. `setup-qemu-action` provides the emulation, `buildx` does the multi-platform build.

---

## Files written (`gke-microservice-app`)

```
.github/workflows/ci-cd.yaml
```

Plus the target it writes into, in the GitOps repo:
```
gke-gitops-infra/apps/microservice/overlays/prod/kustomization.yaml   # images: block
```

---

## One-time setup (exact commands / clicks)

You need three GCP values from your Terraform outputs (Phase 2):

```bash
cd gke-gitops-infra/terraform/envs/prod
terraform output ci_sa_email          # -> GCP_CI_SERVICE_ACCOUNT
terraform output wif_provider_name    # -> GCP_WIF_PROVIDER
terraform output -raw artifact_registry_repo   # confirms GAR path
echo "project: $(terraform output -raw cluster_name)"   # you already know project_id
```

In the **app repo** on GitHub → *Settings → Secrets and variables → Actions*:

**Variables** (not secret):
- `GCP_PROJECT_ID` = your project id
- `GCP_WIF_PROVIDER` = the `wif_provider_name` output (looks like `projects/123.../locations/global/workloadIdentityPools/github-pool/providers/github-provider`)
- `GCP_CI_SERVICE_ACCOUNT` = the `ci_sa_email` output (`github-ci@PROJECT.iam.gserviceaccount.com`)
- `GITOPS_REPO` = `your-user/gke-gitops-infra`

**Secret:**
- `GITOPS_TOKEN` = a fine-grained Personal Access Token (or GitHub App token) with **Contents: read/write** on the GitOps repo only. This lets the `bump-gitops` job push the tag commit.

Trigger it:

```bash
cd gke-microservice-app
git add . && git commit -m "ci: initial pipeline" && git push origin main
# Watch it run:
#   GitHub -> Actions tab -> ci-cd
```

Confirm the image landed:

```bash
gcloud artifacts docker images list \
  us-central1-docker.pkg.dev/$GCP_PROJECT_ID/apps/gke-microservice
```

---

## Gotchas

- **`Permission 'iam.serviceAccounts.getAccessToken' denied`** → the WIF binding doesn't match your repo. Check `github_owner`/`app_repo_name` in Terraform equal your actual `owner/repo`.
- **`denied: Permission artifactregistry.repositories.uploadArtifacts`** → the CI SA is missing `roles/artifactregistry.writer` (it's in the `iam` module; re-apply Terraform).
- **`bump-gitops` push rejected** → `GITOPS_TOKEN` lacks write, or points at the wrong repo.
- **Trivy fails the build** → that's the point. Either bump the dependency, or (if it's a false positive/unfixable) add the CVE id to `.trivyignore`.

---

## Interview Questions & Answers (Phase 4)

**Q1. How does your CI authenticate to GCP without storing a service-account key?**
> It uses Workload Identity Federation. The workflow requests a short-lived GitHub OIDC token via `id-token: write`, and GCP's WIF provider — which I configured to trust only my repo owner — exchanges it for temporary GCP credentials scoped to a CI service account that can only write to Artifact Registry. There's no static JSON key anywhere, so nothing long-lived can leak, and access is automatically scoped and time-limited.

**Q2. Your CI builds and pushes an image but doesn't run `kubectl apply`. How does the deploy actually happen?**
> That's intentional — it's the GitOps model. CI's job ends at producing a trusted, scanned image and then committing the new image tag into the GitOps repo using `kustomize edit set image`. ArgoCD watches that repo, sees the commit, and reconciles the cluster to match. Git stays the single source of truth, CI has no cluster credentials, and every deploy is an auditable Git commit I can revert.

**Q3. Where is security enforced in the pipeline?**
> In two places, and both can fail the build. Trivy first scans the source and dependencies for known CVEs, then after the image is built it scans the image layers too, failing on HIGH or CRITICAL. Combined with `go vet`, `golangci-lint`, and race-enabled tests as an earlier gate, and the non-root distroless base image, security is enforced left-to-right — problems are caught before anything reaches the registry, let alone the cluster.

---

*Next: Phase 5 — install ArgoCD and wire the App-of-Apps so the cluster continuously reconciles to this GitOps repo.*
