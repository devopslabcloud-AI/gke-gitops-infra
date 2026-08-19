#!/usr/bin/env bash
# Phase 7 - Validation, chaos and drift tests.
# Demonstrates: HPA scaling, ArgoCD self-healing, and Grafana/Prometheus alerting.
# Requires: kubectl (pointed at the GKE cluster), and the app deployed via ArgoCD.
set -euo pipefail

NS=microservice
DEP=microservice

host() {
  local ip
  ip=$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  echo "app.$(echo "$ip" | tr '.' '-').sslip.io"
}

case "${1:-help}" in
  # 1) POD CRASH: delete a pod, watch Kubernetes recreate it automatically.
  crash)
    echo ">> Deleting one pod; Deployment controller should recreate it."
    POD=$(kubectl -n $NS get pods -l app=$DEP -o jsonpath='{.items[0].metadata.name}')
    kubectl -n $NS delete pod "$POD"
    kubectl -n $NS get pods -l app=$DEP -w
    ;;

  # 2) TRAFFIC SPIKE: hammer the service, watch the HPA add replicas.
  load)
    HOST=$(host)
    echo ">> Generating load against https://${HOST} ... (Ctrl-C to stop)"
    echo ">> In another terminal run: kubectl -n $NS get hpa $DEP -w"
    # 50 parallel loops of requests
    for i in $(seq 1 50); do
      ( while true; do curl -sk "https://${HOST}/api/v1/items/$RANDOM" >/dev/null; done ) &
    done
    trap 'kill $(jobs -p) 2>/dev/null' EXIT
    wait
    ;;

  # 3) DRIFT: manually change the live cluster; ArgoCD self-heal should revert it.
  drift)
    echo ">> Current replicas in Git-desired state:"
    kubectl -n $NS get deploy $DEP -o jsonpath='{.spec.replicas}'; echo
    echo ">> Manually scaling to 7 (simulating a rogue kubectl edit)..."
    kubectl -n $NS scale deploy/$DEP --replicas=7
    kubectl -n $NS get deploy $DEP
    echo ">> Watch ArgoCD revert replicas back to the Git value (selfHeal)."
    echo ">> Observe with: watch kubectl -n $NS get deploy $DEP"
    kubectl -n $NS get deploy $DEP -w
    ;;

  # 4) DRIFT via image: point live image somewhere bogus; ArgoCD should fix it.
  drift-image)
    echo ">> Setting a bogus image on the live Deployment..."
    kubectl -n $NS set image deploy/$DEP $DEP=nginx:doesnotexist
    echo ">> ArgoCD self-heal should restore the Git-defined image shortly."
    kubectl -n $NS get deploy $DEP -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
    kubectl -n $NS rollout status deploy/$DEP --timeout=120s || true
    ;;

  # 5) Show alert status (needs Prometheus port-forward on :9090).
  alerts)
    echo ">> Port-forward first: kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090"
    curl -s localhost:9090/api/v1/alerts | python3 -m json.tool
    ;;

  *)
    cat <<USAGE
Usage: $0 <command>
  crash        Delete a pod and watch K8s recreate it
  load         Traffic spike to trigger the HPA (watch: kubectl -n $NS get hpa $DEP -w)
  drift        Manually scale replicas; ArgoCD selfHeal reverts it
  drift-image  Set a bogus image; ArgoCD selfHeal restores it
  alerts       Query firing Prometheus alerts (requires port-forward)
USAGE
    ;;
esac
