#!/bin/sh
ALDAAS_PORT="${ALDAAS_PORT:-5432}"
ALDAAS_TTL="${ALDAAS_TTL:-300}"
# Internal Service DNS suffix for direct WebSocket connection (bypasses ALB 60s idle timeout)
# The WorkflowTemplate creates a Service named {{workflow.name}} in this namespace
# with port 8080 (tunnel) + 5432 (postgres)
ALDAAS_NAMESPACE="${ALDAAS_NAMESPACE:-aldaas}"

# Connection mode: "internal" (Service DNS, default) or "external" (ingress wss://)
# - internal: ws://<wf-name>.<namespace>.svc.cluster.local:8080 (bypasses ALB 60s timeout)
# - external: wss://<domain>/<aldaas-fullname>/<token>/<wf-name> (through ingress, for off-cluster clients)
ALDAAS_MODE="${ALDAAS_MODE:-internal}"

# Exponential backoff for re-provisioning (seconds)
BACKOFF=1
MAX_BACKOFF=30

# Retry loop: re-provision on upstream DB loss
# tcp-over-websocket does not exit on dial error (continue in Accept loop).
# We run it in background and monitor upstream DNS with a watchdog.
# When the upstream Service is deleted (DNS NXDOMAIN), we kill the tunnel
# and re-submit a new Argo workflow.
while true; do
    echo "=== Re-provisioning aldaas (backoff=${BACKOFF}s) ==="

    # Session store: ConfigMap (K8s) or /tmp file (fallback)
    SESSION_CM="aldaas-session-${ALDAAS_NAME}"
    aldaas_name=""
    aldaas_full=""

    if [ "$K8S_SESSION_STORE" = "true" ]; then
        # Read from ConfigMap
        aldaas_full=$(kubectl get configmap "$SESSION_CM" -o jsonpath='{.data.workflow}' 2>/dev/null)
        if [ -n "$aldaas_full" ]; then
            echo "ConfigMap $SESSION_CM has saved workflow: $aldaas_full"
            if argo get "$aldaas_full" >/dev/null 2>&1; then
                aldaas_name=$(echo "$aldaas_full" | sed 's|^.*/||')
                echo "Use saved $aldaas_full"
            else
                echo "Saved workflow not found, will re-provision"
                aldaas_full=""
            fi
        fi
    else
        # Fallback: /tmp/aldaas file
        rm -f /tmp/aldaas
        FILE=/tmp/aldaas
        if [ -f "$FILE" ]; then
            echo "save file exists."
            aldaas_full=$(cat $FILE)
            if argo get "$aldaas_full" >/dev/null 2>&1; then
                aldaas_name=$(echo "$aldaas_full" | sed 's|^.*/||')
                echo "Use saved $aldaas_full"
            else
                echo "Not found $aldaas_full"
                aldaas_full=""
            fi
        fi
    fi

    # if no save create new aldaas wf
    if [ -z "$aldaas_name" ]; then
        # argo submit -o name returns "namespace/workflow-name" (e.g. "aldaas/aldaas-dandelion-app-backend-w9xc5")
        # We need just the workflow-name part for Service DNS / ingress path
        aldaas_full=$(argo submit --from workflowtemplate/$ALDAAS_NAME -p ttl=$ALDAAS_TTL -o name)
        if [ $? -ne 0 ]; then
            echo "ERROR: argo submit failed, retrying in ${BACKOFF}s"
            sleep $BACKOFF
            BACKOFF=$((BACKOFF * 2))
            [ $BACKOFF -gt $MAX_BACKOFF ] && BACKOFF=$MAX_BACKOFF
            continue
        fi
        # Strip namespace prefix: "aldaas/wf-name" → "wf-name"
        aldaas_name=$(echo "$aldaas_full" | sed 's|^.*/||')
        # Save to session store
        if [ "$K8S_SESSION_STORE" = "true" ]; then
            kubectl create configmap "$SESSION_CM" --from-literal=workflow="$aldaas_full" --dry-run=client -o yaml | kubectl apply -f -
            echo "Saved workflow to ConfigMap $SESSION_CM"
        else
            echo "$aldaas_full" > /tmp/aldaas
        fi
    fi

    # Wait for the ephemeral DB Service to become available (port 5432)
    # We poll the Service DNS instead of using `argo watch` because:
    # 1. argo watch blocks until the ENTIRE workflow completes
    # 2. We only need to wait until the Service is reachable (after wait-service step)
    # 3. The workflow stays alive (no cleanup-pvc step) — lifecycle is managed by
    #    uptime container → remove EventSource → delete workflow → OwnerReferences
    #    cascade-delete PVC, Deployment, Service, Ingress
    echo "Waiting for ephemeral DB Service $aldaas_name.$ALDAAS_NAMESPACE.svc.cluster.local:5432..."
    SERVICE_READY=0
    for i in $(seq 1 120); do
        if nc -z "$aldaas_name.$ALDAAS_NAMESPACE.svc.cluster.local" 5432 2>/dev/null; then
            echo "DB Service is ready (attempt $i)"
            BACKOFF=1  # reset backoff on success
            SERVICE_READY=1
            break
        fi
        sleep 1
    done
    if [ "$SERVICE_READY" -eq 0 ]; then
        echo "ERROR: DB Service did not become available within 120 seconds"
        sleep $BACKOFF
        BACKOFF=$((BACKOFF * 2))
        [ $BACKOFF -gt $MAX_BACKOFF ] && BACKOFF=$MAX_BACKOFF
        continue
    fi

    nohup sh -c "while true; do curl --connect-timeout 3600 -vv telnet://0.0.0.0:$ALDAAS_PORT; sleep 0.1; done" > /dev/null 2>&1 &

    # Build WebSocket URL based on ALDAAS_MODE
    if [ "$ALDAAS_MODE" = "external" ]; then
        # External mode: through ingress (wss://)
        # URL: wss://<domain>/<aldaas-fullname>/<token>/<wf-name>
        # Requires: ALDAAS_DOMAIN, ALDAAS_TOKEN env vars
        WS_URL="wss://${ALDAAS_DOMAIN}/${ALDAAS_NAME}/${ALDAAS_TOKEN}/${aldaas_name}"
        echo "Connecting (external/ingress): $WS_URL"
    else
        # Internal mode: direct Service DNS (ws://) — bypasses ALB 60s idle timeout
        # Service: <workflow-name>.<namespace>.svc.cluster.local:8080 (tunnel port)
        WS_URL="ws://${aldaas_name}.${ALDAAS_NAMESPACE}.svc.cluster.local:8080"
        echo "Connecting (internal/service-dns): $WS_URL"
    fi

    # Start tcp-over-websocket in background
    # tcp-over-websocket does not exit on dial error (continue in Accept loop).
    # We monitor upstream DNS with a watchdog and kill the tunnel when the
    # Service is deleted (DNS NXDOMAIN).
    tcp-over-websocket client -listen_tcp 0.0.0.0:$ALDAAS_PORT -connect_ws "$WS_URL" &
    TUNNEL_PID=$!

    # Watchdog: monitor upstream Service DNS
    # When the Argo workflow is deleted (TTL expiry / remove EventSource),
    # the Service DNS record is removed. We detect this and trigger re-provisioning.
    # Tolerance: require N consecutive DNS failures before killing the tunnel,
    # to avoid false positives from transient CoreDNS hiccups or network blips.
    DNS_FAIL_COUNT=0
    DNS_FAIL_THRESHOLD=3
    while kill -0 $TUNNEL_PID 2>/dev/null; do
        sleep 10
        if ! nslookup "$aldaas_name.$ALDAAS_NAMESPACE.svc.cluster.local" >/dev/null 2>&1; then
            DNS_FAIL_COUNT=$((DNS_FAIL_COUNT + 1))
            echo "DNS lookup failed ($DNS_FAIL_COUNT/$DNS_FAIL_THRESHOLD) for $aldaas_name.$ALDAAS_NAMESPACE.svc.cluster.local"
            if [ "$DNS_FAIL_COUNT" -ge "$DNS_FAIL_THRESHOLD" ]; then
                echo "Upstream Service DNS gone after $DNS_FAIL_THRESHOLD consecutive failures — re-provisioning"
                kill $TUNNEL_PID 2>/dev/null
                wait $TUNNEL_PID 2>/dev/null
                break
            fi
        else
            DNS_FAIL_COUNT=0
        fi
    done

    # Backoff before retry
    sleep $BACKOFF
    BACKOFF=$((BACKOFF * 2))
    [ $BACKOFF -gt $MAX_BACKOFF ] && BACKOFF=$MAX_BACKOFF
done
