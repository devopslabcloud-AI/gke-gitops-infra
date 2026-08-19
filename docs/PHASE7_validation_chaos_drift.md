# Phase 7 — Validation, Chaos & Drift Testing

## Concepts first (plain English)

This phase *proves* the system works by deliberately breaking things. Three scenarios, each demonstrating a different resilience feature:

1. **Pod crash → Kubernetes self-repair.** Delete a pod. The Deployment controller notices the replica count is short and recreates it. This shows Kubernetes' basic reconciliation and that your readiness probe keeps traffic off the new pod until it's ready.
2. **Traffic spike → HPA autoscaling.** Flood the service with requests. CPU rises past the 60% target, and the HorizontalPodAutoscaler adds replicas (up to 10). When traffic drops, it scales back down. This is elastic scaling under load.
3. **Cluster drift → ArgoCD self-heal.** Manually change the live cluster (`kubectl scale`, or set a bad image). ArgoCD sees the live state no longer matches Git and reverts it automatically. This is the "automated drift correction" headline of GitOps.

Alongside, **Prometheus alert rules** fire when error rate or latency crosses a threshold, and you can watch them go from *pending* → *firing* in Grafana/Alertmanager.

**Why this matters for MTTR.** MTTR = Mean Time To Recovery. Because Kubernetes restarts crashed pods, the HPA absorbs spikes, and ArgoCD reverts drift — all without a human — recovery for these common failures drops from minutes of manual work to seconds of automation.

---

## Files written

```
observability/alerts/microservice-alerts.yaml   # PrometheusRule: error rate, latency, crashloop, target-down
scripts/chaos-drift-test.sh                      # one script, five scenarios
```

The alert rules are auto-deployed by the `observability-extras` ArgoCD app (they're under `observability/`). Commit + push and they go live.

---

## Exact commands (walkthrough)

Make the script executable and open a second terminal for watching:

```bash
cd gke-gitops-infra
chmod +x scripts/chaos-drift-test.sh
git add observability/alerts scripts && git commit -m "feat: alerts + chaos scripts" && git push
```

### Scenario 1 — Pod crash self-repair
```bash
# Terminal A: watch pods
kubectl -n microservice get pods -l app=microservice -w
# Terminal B:
./scripts/chaos-drift-test.sh crash
# EXPECT: the deleted pod's replacement appears within seconds; Ready 1/1 after warmup.
```

### Scenario 2 — Traffic spike triggers the HPA
```bash
# Terminal A: watch the autoscaler
kubectl -n microservice get hpa microservice -w
# Terminal B: generate load
./scripts/chaos-drift-test.sh load
# EXPECT: TARGETS climbs above 60%, REPLICAS grows 2 -> ... -> up to 10.
# Stop the load (Ctrl-C); replicas scale back down after the cooldown.
```

### Scenario 3 — Manual drift, ArgoCD self-heals
```bash
# Terminal A: watch the deployment + ArgoCD
watch kubectl -n microservice get deploy microservice
# (or the ArgoCD UI: the app flips to OutOfSync, then back to Synced)
# Terminal B:
./scripts/chaos-drift-test.sh drift          # scales to 7 behind ArgoCD's back
# EXPECT: replicas briefly show 7, then ArgoCD reverts to the Git value (2).

./scripts/chaos-drift-test.sh drift-image    # sets a bogus image
# EXPECT: ArgoCD restores the correct Artifact Registry image automatically.
```

### Scenario 4 — Watch alerts fire
```bash
# Port-forward Prometheus and Alertmanager
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090 &
# Cause errors/latency (e.g. delete pods repeatedly during load), then:
./scripts/chaos-drift-test.sh alerts
# Or open http://localhost:9090/alerts and watch MicroserviceHighErrorRate go pending -> firing.
```

### Prove it in the dashboard
While running the load test, open Grafana → **Microservice - Golden Signals**. You'll see Traffic climb, Latency p95 move, Saturation (in-flight) rise, and — if you crash pods mid-load — the Errors panel and the alert light up.

---

## What "done" looks like (portfolio checklist)

- `kubectl get nodes` → multi-zone nodes Ready (Terraform).
- `argocd app list` → all apps **Synced / Healthy**.
- `https://app.<LB_IP>.sslip.io/api/v1/items/1` → 200 with a **valid Let's Encrypt cert**.
- Deleting a pod → auto-recreated; HPA scales under load.
- `kubectl scale` drift → **reverted by ArgoCD** within a minute.
- Grafana Golden Signals dashboard populated; alerts fire on induced failure.

Take screenshots of each — they're the proof for your LinkedIn post and interviews.

> Remember to `terraform destroy` when you're done to stop billing.

---

## Interview Questions & Answers (Phase 7)

**Q1. How does your setup reduce MTTR, concretely?**
> Three automated recovery loops handle the most common failures with no human in the path. Kubernetes recreates crashed pods and keeps traffic off them until the readiness probe passes; the HPA absorbs traffic spikes by adding replicas up to a max; and ArgoCD reverts any manual drift back to Git. So for a crashed pod, a load spike, or a fat-fingered `kubectl edit`, recovery is seconds of automation instead of minutes of manual firefighting. On top of that, Prometheus alerts surface error-rate and latency regressions early, so we detect issues before users report them.

**Q2. Demonstrate that GitOps actually prevents configuration drift.**
> I scale the live Deployment directly with `kubectl scale --replicas=7`, which is exactly the kind of out-of-band change that causes drift. Because the ArgoCD Application has `selfHeal: true`, it detects that live state no longer matches the manifests in Git and reverts the replica count back to the committed value within its reconcile window. The same happens if I set a bogus image. The only way to make a lasting change is to commit it to Git and let ArgoCD roll it out — which means every change is reviewed and auditable.

**Q3. How do you achieve zero-downtime deployments here?**
> Several things combine. The Deployment uses a RollingUpdate strategy with `maxUnavailable: 0`, so old pods keep serving until new ones are Ready. Readiness probes gate traffic — a new pod only joins the load balancer once `/readyz` returns 200 after warmup. And on shutdown the app catches SIGTERM, flips readiness to false so it's drained from the load balancer, then finishes in-flight requests before exiting. So during a rollout there's always a healthy pod serving, and no request hits a pod that's starting up or shutting down.

---

*Next: the LinkedIn showcase post.*
