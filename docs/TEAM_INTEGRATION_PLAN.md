# Team Integration Plan (4 people, start → end)

## The one rule that avoids chaos
Everything downstream depends on **(a) the GKE cluster + Artifact Registry** (Terraform outputs) and **(b) the two Git repos**. So the team's first job — together — is to agree the shared naming "contract" and stand up those foundations. Once the cluster and registry exist, the rest can run in parallel tracks that meet at defined handoffs.

---

## Step 0 — Shared config "contract" (whole team, ~1 hour, do this FIRST)
Agree these values and write them in a pinned doc / Slack. Every repo hard-codes them, so disagreeing later = painful rework.

| Key | Example | Used by |
|---|---|---|
| `PROJECT_ID` | `my-gcp-proj` | Terraform, CI, manifests |
| `REGION` | `us-central1` | everything |
| `CLUSTER_NAME` | `gitops-gke` | Terraform, kubeconfig |
| GitHub owner (`REPLACE_OWNER`) | `our-org` | CI, ArgoCD repoURLs |
| App repo name | `gke-microservice-app` | CI, WIF |
| GitOps repo name | `gke-gitops-infra` | CI, ArgoCD |
| Go module path | `github.com/our-org/gke-microservice-app` | app code |
| Image name | `gke-microservice` | CI, Kustomize |
| tfstate bucket | `my-gcp-proj-tfstate` | Terraform backend |

Also do now: create the two GitHub repos, create the GCP project + enable billing, and give everyone `roles/owner` on the project for the build phase (tighten later).

---

## The dependency chain (what blocks what)
```
Step 0 (config + repos)
   │
   ├─► TERRAFORM ──► cluster + Artifact Registry + WIF/IAM outputs
   │        │
   │        ├──────────────► CI can push images (needs registry + WIF)
   │        └──────────────► ArgoCD install (needs cluster)
   │                              │
   │                              ├─► platform apps (nginx, cert-manager)
   │                              │        └─► LB IP ─► set sslip host
   │                              ├─► microservice app (needs image tag from CI)
   │                              └─► observability (prometheus/grafana/otel)
   │                                       └─► chaos + drift validation
   │
   └─► APP CODE (Go + Docker) can be built/tested locally with NO cluster
```
The long pole is Terraform (10–15 min applies). Kick it off early; build the app in parallel while it runs.

---

## Who does what (4 roles)
- **P1 — Cloud/Infra lead.** Owns `terraform/` (Phase 2), GCP project setup, remote state bucket, ArgoCD *install*, and Workload Identity / WIF. Produces the Terraform outputs the others need.
- **P2 — App developer.** Owns `gke-microservice-app` Go code + Dockerfile (Phase 3), unit tests, local `docker build`. Can work fully offline from the cluster until CI.
- **P3 — CI/CD + GitOps engineer.** Owns GitHub Actions (Phase 4) and the ArgoCD App-of-Apps + Kustomize manifests (Phase 5). Consumes P1's WIF/registry outputs; wires the CI→GitOps tag-bump.
- **P4 — Observability/SRE.** Owns kube-prometheus-stack + OTel + ServiceMonitor + dashboard + alerts (Phase 6) and the chaos/drift validation (Phase 7).

---

## Milestone timeline with handoffs (the integration points)

**M0 — Foundations (all).** Config contract, 2 repos created, GCP project + APIs, state bucket. Push the scaffold from both zips into the repos, each person on a branch.

**M1 — Cluster up (P1).** `terraform apply` succeeds. **Handoff:** P1 posts `terraform output` values — `artifact_registry_repo`, `wif_provider_name`, `ci_sa_email`, and the `get_credentials_command`. P3 and P4 are unblocked. Everyone runs the get-credentials command to get kubeconfig.

**M2 — App builds green (P2), parallel with M1.** `go mod tidy`, `go build`, `docker build` all pass locally; PR merged to app repo `main`. No cluster needed.

**M3 — CI pushes first image (P3).** With M1 outputs set as GitHub repo Variables + `GITOPS_TOKEN` secret, a push to app `main` runs the pipeline and lands the first image in Artifact Registry **and** commits a tag bump into the GitOps repo. **Handoff:** the overlay `kustomization.yaml` now references a real image tag.

**M4 — GitOps bootstrapped (P1 + P3).** Replace `REPLACE_OWNER`/`PROJECT_ID` placeholders in the GitOps repo and commit. Install ArgoCD, apply the AppProject + `root-app.yaml`. Platform apps sync. **Handoff:** P1 grabs the NGINX LoadBalancer IP; team sets the `sslip.io` host in the overlay and ClusterIssuer, commits, ArgoCD re-syncs.

**M5 — App live (integration checkpoint).** `argocd app list` shows microservice **Synced/Healthy**; `https://app.<LB_IP>.sslip.io/api/v1/items/1` returns 200 with a valid Let's Encrypt cert. This is the "it works end-to-end" moment.

**M6 — Observability online (P4).** Commit the observability child apps + ServiceMonitor + dashboard + alerts. Prometheus target for the app is UP; Grafana Golden Signals dashboard populates under load.

**M7 — Validation (P4 + all).** Run `scripts/chaos-drift-test.sh` scenarios (pod crash, HPA load, drift → self-heal). Capture screenshots/GIFs of each.

**M8 — Showcase (all).** Export the architecture diagram, finalize READMEs, publish the LinkedIn post with repo links in the first comment.

---

## How to actually collaborate in Git
- Each person works on a **feature branch**, opens a **PR**, gets one review, merges to `main`. Protect `main` on both repos.
- The GitOps repo `main` is production — ArgoCD deploys whatever is there. Treat every merge as a deploy. Small PRs.
- CI's automated tag-bump commits to GitOps `main` directly (via `GITOPS_TOKEN`); don't fight it — never hand-edit the `images:` block, let CI own it.
- Rotate a **daily 15-min sync** during build week to unblock handoffs (M1 output sharing is the critical one).

---

## Where YOU start, right now (today)
1. **All:** fill in the Step 0 config table; create the 2 GitHub repos and the GCP project.
2. **P1:** start Terraform immediately — it's the long pole. Target: cluster + registry live today.
3. **P2:** in parallel, get the Go app building and `docker build` passing locally.
4. **P3 & P4:** replace placeholders in the GitOps repo, review the ArgoCD/observability manifests, and prep GitHub Actions Variables so you're ready the second P1 posts the Terraform outputs.

Then follow the milestones M1→M8 in order. The only hard sequencing is: **Terraform before ArgoCD**, **CI/registry before the app can deploy**, **platform (nginx) before the LB IP/host**, and **app deployed before observability shows data.**
