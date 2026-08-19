# Phase 5 — GitOps with ArgoCD (App-of-Apps)

## Concepts first (plain English)

**What ArgoCD does.** It's a controller that lives in the cluster and continuously compares "what Git says" (desired state) with "what's actually running" (live state). If they differ, it either shows a diff or — with auto-sync on — makes the cluster match Git. Git becomes the single source of truth.

**Sync, prune, self-heal — the three switches:**
- **automated sync** — apply changes from Git automatically, no human `kubectl apply`.
- **prune** — if you *delete* something from Git, delete it from the cluster too.
- **selfHeal** — if someone changes the cluster *directly* (a manual `kubectl edit`), ArgoCD reverts it back to Git. This is the automated drift correction we'll demo in Phase 7.

**App-of-Apps pattern.** Instead of applying a dozen apps by hand, you apply **one** "root" Application. The root points at a folder of child Application manifests (`argocd/apps/`), and ArgoCD creates each child. Bootstrapping the whole platform becomes a single command. Add a new component later by dropping one YAML file in that folder and committing — no manual step.

**Sync waves (ordering).** Some things must exist before others: cert-manager's CRDs must be installed before you can create a `ClusterIssuer`; NGINX must be up before ingress works. The annotation `argocd.argoproj.io/sync-wave: "N"` orders them — wave 0 (ingress, cert-manager, sealed-secrets) → wave 1 (ClusterIssuer) → wave 2 (the microservice).

**Where Helm fits.** Platform components (NGINX, cert-manager, sealed-secrets) are public Helm charts. Each child Application points at the chart's repo and passes inline `helm.values`. Our own app uses Kustomize instead. ArgoCD speaks both natively.

---

## Files written

```
argocd/
├── projects/platform-project.yaml   # AppProject = RBAC + allowed repos/destinations
├── bootstrap/root-app.yaml          # the App-of-Apps root (apply this by hand)
└── apps/                            # child Applications (ArgoCD manages these)
    ├── ingress-nginx.yaml   (wave 0)
    ├── cert-manager.yaml    (wave 0)
    ├── sealed-secrets.yaml  (wave 0)
    ├── cluster-issuer.yaml  (wave 1)
    └── microservice.yaml    (wave 2)
platform/cert-manager/cluster-issuer.yaml   # Let's Encrypt HTTP-01 issuer
```
(Phase 6 adds `kube-prometheus-stack.yaml` and `opentelemetry-collector.yaml` into `argocd/apps/`.)

---

## Exact commands

**1. Replace the repo placeholder with your real GitOps repo** (all manifests reference it):

```bash
cd gke-gitops-infra
export GH_OWNER="my-github-username"
grep -rl 'REPLACE_OWNER' . | xargs sed -i "s#REPLACE_OWNER#${GH_OWNER}#g"   # macOS: sed -i ''
# also set your GCP project in the app manifests:
export PROJECT_ID="my-gcp-project-id"
grep -rl 'PROJECT_ID' apps/ | xargs sed -i "s#PROJECT_ID#${PROJECT_ID}#g"
git add . && git commit -m "chore: set repo + project" && git push
```

**2. Install ArgoCD into the cluster:**

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait until the ArgoCD pods are Ready
kubectl -n argocd rollout status deploy/argocd-server --timeout=180s
```

**3. Log into the ArgoCD UI (optional but great for demos/screenshots):**

```bash
# initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# port-forward the UI to your laptop
kubectl -n argocd port-forward svc/argocd-server 8080:443
# open https://localhost:8080  (user: admin)
```

**4. Bootstrap everything — apply the project + root app ONCE:**

```bash
kubectl apply -f argocd/projects/platform-project.yaml
kubectl apply -f argocd/bootstrap/root-app.yaml

# Watch the platform come to life
kubectl -n argocd get applications -w
```

**5. Get the NGINX LoadBalancer IP, then set the sslip.io host:**

```bash
# Wait for the external IP to be assigned (may take 1-2 min)
kubectl -n ingress-nginx get svc ingress-nginx-controller -w

export LB_IP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "LoadBalancer IP: $LB_IP"

# sslip.io host uses dashes: 34.120.8.15 -> 34-120-8-15
export HOST="app.$(echo $LB_IP | tr '.' '-').sslip.io"
echo "Host: $HOST"

# Patch the overlay + issuer to the real host, commit, let ArgoCD re-sync
sed -i "s#app.REPLACE_LB_IP.sslip.io#${HOST}#g" \
  apps/microservice/base/ingress.yaml \
  apps/microservice/overlays/prod/patch-ingress-host.yaml
git add . && git commit -m "feat: set ingress host to $HOST" && git push
```

**6. Verify the app is live and TLS issued:**

```bash
kubectl -n microservice get deploy,svc,ingress,hpa
kubectl get certificate -n microservice          # READY should become True
curl -s "https://${HOST}/api/v1/items/7"          # valid Let's Encrypt cert
```

---

## Gotchas

- **App stuck `OutOfSync`/`Unknown`** → repoURL still says `REPLACE_OWNER`, or the repo is private and ArgoCD has no credentials (add via `argocd repo add`).
- **Certificate stays `False`** → the sslip.io host must resolve to the *NGINX LoadBalancer IP*; re-check step 5. Let's Encrypt HTTP-01 needs the `/.well-known/...` path reachable over port 80.
- **ClusterIssuer errors "no kind ClusterIssuer"** → cert-manager CRDs weren't ready; the sync-wave handles ordering, just let ArgoCD retry.

---

## Interview Questions & Answers (Phase 5)

**Q1. What is the App-of-Apps pattern and why use it?**
> It's a single root ArgoCD Application that points at a directory of *other* Application manifests. Applying that one root bootstraps the entire platform — ingress, cert-manager, secrets, and the app — and afterwards adding a component is just committing one more YAML file into that folder. It gives you one declarative entry point, consistent RBAC through a shared AppProject, and no snowflake manual steps.

**Q2. How does ArgoCD handle someone manually editing a live resource?**
> With `selfHeal: true`, ArgoCD treats Git as the source of truth. If someone runs `kubectl edit` and changes, say, the replica count, ArgoCD detects the drift on its next reconcile and reverts the cluster back to what Git says. Combined with `prune`, deleting something from Git also removes it from the cluster. That means the cluster can't quietly drift away from the reviewed, version-controlled state.

**Q3. Your app uses Kustomize but the platform uses Helm — how does that coexist in ArgoCD?**
> ArgoCD renders both natively. Each platform child Application references a Helm chart repo with inline values; the microservice Application points at a Kustomize overlay path. Sync waves order them so dependencies like cert-manager CRDs exist before the ClusterIssuer and the app. That mix is common in real clusters — Helm for third-party components, Kustomize for your own manifests where you want plain, patch-based overlays.

---

*Next: Phase 6 — the observability stack (kube-prometheus-stack + OpenTelemetry Collector, a ServiceMonitor for our app, and a Golden Signals Grafana dashboard).*
