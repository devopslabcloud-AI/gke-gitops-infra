# Phase 2 — Infrastructure as Code (Terraform for GKE)

## Concepts first (plain English)

**Infrastructure as Code (IaC).** Instead of clicking around the GCP console to create a cluster, you *describe* what you want in text files. Terraform reads those files and makes the cloud match them. The big win: your infrastructure is versioned in Git, reviewable, and reproducible. Delete everything and recreate it identically with one command.

**Terraform in one sentence.** You write `.tf` files (desired state), Terraform compares them to what actually exists (real state, stored in a *state file*), and applies only the difference.

**Modules.** A module is a reusable folder of Terraform (like a function). We built three — `vpc`, `gke`, `iam` — and the `envs/prod` folder just *calls* them with specific values. This keeps things DRY and lets you add a `staging` env later by copying one small folder.

**VPC-native cluster + secondary ranges.** A GKE cluster needs IPs for three things: nodes, Pods, and Services. "VPC-native" means Pods get real IPs from dedicated *secondary ranges* on the subnet (`pods` and `services`). This is the modern default and required for features like Workload Identity and network policy.

**Regional (multi-zone) cluster.** Setting `location = region` (not a single zone) spreads the control plane and nodes across multiple zones. If one Google data-center zone fails, your app stays up. That's the "highly available / production-grade" checkbox.

**Managed node pool + autoscaling.** Nodes are the VMs your Pods run on. A *node pool* is a group of identical VMs. `auto_repair`/`auto_upgrade` keep them healthy and patched; the *cluster autoscaler* (`min_nodes`..`max_nodes`) adds/removes VMs based on demand so you don't pay for idle capacity.

**Workload Identity (the security highlight).** Normally an app talks to Google APIs using a downloaded JSON key — a huge leak risk. Workload Identity lets a *Kubernetes* ServiceAccount securely impersonate a *Google* service account with **zero keys**. We wire the binding in the `iam` module.

**Workload Identity Federation (WIF) for CI.** Same idea, but for GitHub Actions. GitHub hands GCP a short-lived OIDC token proving "I'm the CI job for repo X," and GCP trusts it. No service-account JSON key ever lives in GitHub secrets.

**Remote state (GCS backend).** The state file is Terraform's memory of what it built. We store it in a Google Cloud Storage bucket so it's shared across your team/machines and locked during applies (no two people corrupting it at once).

---

## What we built

```
terraform/
├── modules/
│   ├── vpc/    # network, subnet + pod/service secondary ranges, Cloud NAT
│   ├── gke/    # regional cluster, Workload Identity, autoscaling node pool
│   └── iam/    # node SA (least priv), app GSA + WI binding, WIF for GitHub CI
└── envs/prod/  # main.tf split into vpc.tf, gke.tf, iam.tf + variables/outputs
```

The `prod` env also creates an **Artifact Registry** Docker repo where Phase 4 will push images.

---

## Exact commands (run top to bottom)

> Prereqs: install the `gcloud` CLI and `terraform >= 1.6`. Replace `PROJECT_ID` and `GH_OWNER`.

```bash
# 0. Set shell variables you'll reuse
export PROJECT_ID="my-gcp-project-id"
export REGION="us-central1"
export GH_OWNER="my-github-username"

# 1. Log in and pick the project
gcloud auth login
gcloud config set project "$PROJECT_ID"

# 2. Give Terraform application-default credentials
gcloud auth application-default login

# 3. Enable the GCP APIs this project needs
gcloud services enable \
  container.googleapis.com \
  compute.googleapis.com \
  artifactregistry.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  --project "$PROJECT_ID"

# 4. Create the GCS bucket that holds Terraform state (name must be globally unique)
export TF_STATE_BUCKET="${PROJECT_ID}-tfstate"
gcloud storage buckets create "gs://${TF_STATE_BUCKET}" \
  --project "$PROJECT_ID" --location "$REGION" --uniform-bucket-level-access
gcloud storage buckets update "gs://${TF_STATE_BUCKET}" --versioning   # keep state history
```

Now point the backend at your bucket. Edit `terraform/envs/prod/versions.tf` and set
`bucket = "REPLACE_ME-tfstate"` to your real bucket name (`${PROJECT_ID}-tfstate`).

```bash
# 5. Create your tfvars from the example
cd terraform/envs/prod
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set project_id and github_owner

# 6. Initialize (downloads providers, connects the GCS backend)
terraform init

# 7. Format + validate (catches typos before touching the cloud)
terraform fmt -recursive
terraform validate

# 8. Preview exactly what will be created (nothing is built yet)
terraform plan -out tfplan

# 9. Build it (takes ~10-15 min for a GKE cluster)
terraform apply tfplan

# 10. Read the outputs (cluster name, registry path, the get-credentials command)
terraform output
```

Connect `kubectl` to the new cluster using the output command:

```bash
gcloud container clusters get-credentials gitops-gke --region "$REGION" --project "$PROJECT_ID"

# Verify you're connected and nodes are Ready
kubectl get nodes -o wide
kubectl cluster-info
```

**Tear-down (to stop billing when you're done demoing):**

```bash
cd terraform/envs/prod
terraform destroy      # type 'yes' to confirm
```

> Cost tip: a small `e2-standard-2` node pool + regional control plane runs a few dollars/day. Always `terraform destroy` after a demo session, or scale `min_nodes`/`max_nodes` down.

---

## Common gotchas (so you don't get stuck)

- **`terraform init` fails on the backend** → the GCS bucket name in `versions.tf` doesn't match the bucket you created, or the bucket doesn't exist yet.
- **`Error 403 ... API not enabled`** → re-run step 3; API enablement can take a minute to propagate.
- **`quota exceeded` on apply** → lower `max_nodes` or pick a region with more quota.
- **Nodes never become Ready** → almost always a networking/CIDR overlap; make sure `subnet_cidr`, `pods_cidr`, `services_cidr` don't overlap each other.

---

## Interview Questions & Answers (Phase 2)

**Q1. Why use a regional GKE cluster instead of zonal, and what did you do for node scaling?**
> A regional cluster replicates the control plane and node pool across multiple zones in a region, so a single-zone outage doesn't take the app down — that's the high-availability requirement for production. For nodes I used a managed node pool with the cluster autoscaler set to a min/max range, plus `auto_repair` and `auto_upgrade`, so capacity follows demand and Google keeps the nodes patched without manual work.

**Q2. Explain Workload Identity and why it's more secure than a service-account key.**
> Workload Identity lets a Kubernetes ServiceAccount impersonate a Google service account without any downloaded JSON key. The old way — mounting a static key file in the pod — means a leaked key gives an attacker long-lived access. With Workload Identity there's no key to leak; GKE brokers short-lived, automatically-rotated credentials, and the binding is scoped to one exact namespace/ServiceAccount. I extended the same keyless model to CI using Workload Identity Federation, so GitHub Actions authenticates to GCP with a short-lived OIDC token instead of a stored key.

**Q3. How is your Terraform structured for reuse, and where does the state live?**
> I split it into reusable modules — `vpc`, `gke`, and `iam` — and a thin `envs/prod` layer that just passes variables into those modules. To add a staging environment I'd copy the small env folder and change a few values; the modules stay untouched. State is stored remotely in a versioned GCS bucket via the `gcs` backend, which gives shared state and state locking so concurrent applies can't corrupt it. I always run `terraform plan` first to review the diff before applying.

---

*Next: Phase 3 — the Go microservice (`/healthz`, `/readyz`, `/metrics`, JSON logs, OTel) and a hardened multi-stage, non-root Dockerfile.*
