# Phase 6 — Observability Stack

## Concepts first (plain English)

**The three pillars.** Observability = **metrics** (numbers over time: RPS, latency), **logs** (discrete events: our JSON lines), and **traces** (the path of one request across services). We cover metrics + traces here; logs already flow to stdout → GKE logging.

**kube-prometheus-stack (one Helm chart, whole stack).** It installs Prometheus (scrapes + stores metrics), Grafana (dashboards), Alertmanager (alerts), and the **Prometheus Operator**, which lets you configure scraping with Kubernetes CRDs instead of editing a config file.

**ServiceMonitor (the magic CRD).** Instead of hand-editing Prometheus config to add our app, we create a `ServiceMonitor` — a small YAML that says "scrape any Service labelled `app: microservice` on its `http` port at `/metrics` every 15s." The operator sees it and reconfigures Prometheus automatically. We set `serviceMonitorSelectorNilUsesHelmValues: false` so Prometheus picks up our ServiceMonitor even though it's in a different namespace.

**OpenTelemetry Collector (the universal ingest pipe).** A vendor-neutral agent that *receives* telemetry (our app pushes traces via OTLP on port 4317), *processes* it (batching), and *exports* it onward. Apps talk only to the Collector, so you can swap backends (Jaeger, Tempo, Datadog) without touching app code. Our app's `OTEL_EXPORTER_OTLP_ENDPOINT` points at the Collector's in-cluster DNS name.

**Golden Signals.** Google SRE's four must-watch signals, all in one dashboard:
- **Latency** — p50/p95/p99 from the histogram.
- **Traffic** — requests/sec by route.
- **Errors** — 5xx ratio.
- **Saturation** — in-flight requests + CPU.

**Dashboard as code.** The dashboard is a JSON file wrapped in a ConfigMap labelled `grafana_dashboard: "1"`. Grafana's sidecar watches for that label and auto-imports the dashboard — no clicking in the UI, and it's version-controlled in Git like everything else.

---

## Files written

```
argocd/apps/kube-prometheus-stack.yaml     # Prometheus + Grafana + Alertmanager (Helm)
argocd/apps/opentelemetry-collector.yaml   # OTel Collector (Helm)
argocd/apps/observability-extras.yaml      # syncs ServiceMonitor + dashboard
observability/servicemonitors/microservice-servicemonitor.yaml
observability/dashboards/golden-signals-dashboard.json   # the dashboard model
observability/dashboards/golden-signals-configmap.yaml   # sidecar auto-loads this
```

Because these child apps live in `argocd/apps/`, the **root app from Phase 5 deploys them automatically** — just commit and push.

---

## Exact commands

```bash
cd gke-gitops-infra
git add argocd/apps observability
git commit -m "feat: observability stack (prometheus, grafana, otel, dashboard)"
git push
# ArgoCD (root-app) picks up the new child apps within ~3 min, or force it:
#   argocd app sync root-app

# Watch the stack come up
kubectl -n monitoring get pods -w
kubectl -n observability get pods

# Confirm Prometheus is scraping our app (Status > Targets should show it)
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
#   open http://localhost:9090/targets  -> look for "microservice"

# Open Grafana (user: admin, password: admin from the demo values)
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
#   open http://localhost:3000  -> Dashboards -> "Microservice - Golden Signals"
```

Generate some traffic so the panels light up:

```bash
export HOST="app.$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' | tr '.' '-').sslip.io"
for i in $(seq 1 500); do curl -s "https://${HOST}/api/v1/items/$i" >/dev/null; done
```

Verify custom metrics are being collected (PromQL in the Prometheus UI):

```promql
sum(rate(http_requests_total[5m])) by (route)
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))
```

---

## Gotchas

- **Dashboard doesn't appear in Grafana** → the ConfigMap must carry label `grafana_dashboard: "1"` and the Grafana sidecar must be enabled (it is, in our values). Give the sidecar ~1 min.
- **`microservice` target missing in Prometheus** → the Service port name must be `http` and match the ServiceMonitor's `port: http`; also confirm `serviceMonitorSelectorNilUsesHelmValues: false`.
- **CRD apply errors on first sync** → the stack ships huge CRDs; we enabled `ServerSideApply=true` to handle them. Let ArgoCD retry.
- **No traces** → confirm the app pod has `OTEL_EXPORTER_OTLP_ENDPOINT` set to `otel-collector-opentelemetry-collector.observability.svc.cluster.local:4317` and the collector pod is Running.

---

## Interview Questions & Answers (Phase 6)

**Q1. How does Prometheus know to scrape your application?**
> Through a ServiceMonitor CRD, which the Prometheus Operator reconciles into scrape config automatically. My ServiceMonitor selects the Service by its `app: microservice` label and scrapes the named `http` port at `/metrics` every 15 seconds. I never edit Prometheus config by hand — I just declare intent as a Kubernetes object, which is the operator pattern. I also configured Prometheus to consider ServiceMonitors cluster-wide so it picks mine up across namespaces.

**Q2. What are the Golden Signals and how does your dashboard represent them?**
> They're Google SRE's four key signals: latency, traffic, errors, and saturation. My dashboard maps each to a panel driven by the custom metrics the app exposes — traffic is requests/sec by route from the counter, errors is the 5xx ratio, latency is p50/p95/p99 computed from the duration histogram with `histogram_quantile`, and saturation is in-flight requests plus container CPU. The dashboard is stored as JSON in Git and auto-loaded by Grafana's sidecar, so it's dashboard-as-code, not manual clicking.

**Q3. Why put an OpenTelemetry Collector between your app and the backend?**
> It decouples instrumentation from the backend. The app only knows how to push OTLP to the Collector; the Collector decides where telemetry goes and can batch, filter, or re-route it. If we later switch tracing backends — say from a debug exporter to Tempo or Jaeger — we change the Collector config, not the application. It's a single, vendor-neutral ingest point for traces and metrics across every service.

---

*Next: Phase 7 — validation, chaos and drift testing to prove self-healing and alerting actually work.*
