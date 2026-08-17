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
#   Requires: ALDAAS_DOMAIN (e.g. hr-backend.aldaas.dandelion-civilization.com)
#   Backward compat: ALDAAS_SERVER or ALDAAS_HOST also accepted as ALDAAS_DOMAIN
ALDAAS_MODE="${ALDAAS_MODE:-internal}"

# External mode domain: accept ALDAAS_DOMAIN, ALDAAS_SERVER, or ALDAAS_HOST (priority order)
if [ -z "$ALDAAS_DOMAIN" ]; then
    ALDAAS_DOMAIN="${ALDAAS_SERVER:-${ALDAAS_HOST:-}}"
fi

# Exponential backoff for re-provisioning (seconds)
BACKOFF=1
MAX_BACKOFF=30

# Retry loop: re-provision on upstream DB loss
# tcp-over-websocket does not exit on dial error (continue in Accept loop).
# We run it in background and monitor upstream with a watchdog.
# When the upstream Service is deleted (DNS NXDOMAIN) or WebSocket dies,
# we kill the tunnel and re-submit a new Argo workflow.
while true; do
    echo "=== Re-provisioning aldaas (backoff=${BACKOFF}s, mode=${ALDAAS_MODE}) ==="

    # Session store: ConfigMap (K8s) or /tmp file (fallback)
    # ALDAAS_SESSION_ID makes ConfigMap unique per-deployment (e.g. 72536668-review-feature-hr-9oqso9)
    # Falls back to ALDAAS_NAME if not set (backward compatibility, but unsafe in shared namespaces)
    SESSION_ID="${ALDAAS_SESSION_ID:-$ALDAAS_NAME}"
    SESSION_CM="aldaas-session-${SESSION_ID}"
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

    # Wait for the ephemeral DB to become available
    # - internal mode: poll Service DNS (nc -z <wf>.<ns>.svc.cluster.local:5432)
    # - external mode: poll Argo workflow status (argo get <wf> | grep Succeeded/Running)
    #   We can't use nc on internal DNS from outside the cluster.
    #   Instead we wait for the workflow to reach "Running" with all steps complete
    #   by checking argo get output for "Succeeded" or "Running" with progress complete.
    echo "Waiting for ephemeral DB (mode=${ALDAAS_MODE})..."
    SERVICE_READY=0
    for i in $(seq 1 120); do
        if [ "$ALDAAS_MODE" = "external" ]; then
            # External mode: check Argo workflow status via text output
            # (argo get -o json doesn't work through external gRPC proxy)
            # We parse the text output for Status and Progress lines.
            WF_OUTPUT=$(argo get "$aldaas_full" 2>/dev/null)
            WF_STATUS=$(echo "$WF_OUTPUT" | grep '^Status:' | awk '{print $2}')
            WF_PROGRESS=$(echo "$WF_OUTPUT" | grep '^Progress:' | awk '{print $2}')
            # Status: Running = workflow alive, Succeeded = all steps done
            # Progress: "N/M" — when N=M and N>0, all steps complete (DB ready)
            if [ "$WF_STATUS" = "Running" ] || [ "$WF_STATUS" = "Succeeded" ]; then
                if echo "$WF_PROGRESS" | grep -q '/'; then
                    DONE=$(echo "$WF_PROGRESS" | cut -d'/' -f1)
                    TOTAL=$(echo "$WF_PROGRESS" | cut -d'/' -f2)
                    if [ "$DONE" = "$TOTAL" ] && [ "$DONE" -gt 0 ] 2>/dev/null; then
                        echo "DB Service is ready (workflow progress $WF_PROGRESS, attempt $i)"
                        BACKOFF=1
                        SERVICE_READY=1
                        break
                    fi
                fi
            fi
        else
            # Internal mode: poll Service DNS directly
            if nc -z "$aldaas_name.$ALDAAS_NAMESPACE.svc.cluster.local" 5432 2>/dev/null; then
                echo "DB Service is ready (attempt $i)"
                BACKOFF=1  # reset backoff on success
                SERVICE_READY=1
                break
            fi
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
        # Requires: ALDAAS_DOMAIN (or ALDAAS_SERVER/ALDAAS_HOST as fallback), ALDAAS_TOKEN env vars
        if [ -z "$ALDAAS_DOMAIN" ]; then
            echo "ERROR: ALDAAS_MODE=external but ALDAAS_DOMAIN is not set"
            echo "Set ALDAAS_DOMAIN (or ALDAAS_SERVER or ALDAAS_HOST) to the ingress hostname"
            echo "Example: ALDAAS_DOMAIN=hr-backend.aldaas.dandelion-civilization.com"
            sleep $BACKOFF
            BACKOFF=$((BACKOFF * 2))
            [ $BACKOFF -gt $MAX_BACKOFF ] && BACKOFF=$MAX_BACKOFF
            continue
        fi
        WS_URL="wss://${ALDAAS_DOMAIN}/${ALDAAS_NAME}/${ALDAAS_TOKEN}/${aldaas_name}"
        echo "Connecting (external/ingress): wss://${ALDAAS_DOMAIN}/${ALDAAS_NAME}/<token>/${aldaas_name}"
    else
        # Internal mode: direct Service DNS (ws://) — bypasses ALB 60s idle timeout
        # Service: <workflow-name>.<namespace>.svc.cluster.local:8080 (tunnel port)
        WS_URL="ws://${aldaas_name}.${ALDAAS_NAMESPACE}.svc.cluster.local:8080"
        echo "Connecting (internal/service-dns): $WS_URL"
    fi

    # Start tcp-over-websocket in background
    # tcp-over-websocket does not exit on dial error (continue in Accept loop).
    # We monitor upstream with a watchdog and kill the tunnel when the
    # upstream is deleted.
    tcp-over-websocket client -listen_tcp 0.0.0.0:$ALDAAS_PORT -connect_ws "$WS_URL" &
    TUNNEL_PID=$!

    # Watchdog: monitor upstream availability
    # - internal mode: check Service DNS (nslookup <wf>.<ns>.svc.cluster.local)
    # - external mode: check Argo workflow status (argo get <wf>)
    # When the Argo workflow is deleted (TTL expiry / remove EventSource),
    # the upstream is removed. We detect this and trigger re-provisioning.
    # Tolerance: require N consecutive failures before killing the tunnel,
    # to avoid false positives from transient hiccups.
    FAIL_COUNT=0
    FAIL_THRESHOLD=3
    while kill -0 $TUNNEL_PID 2>/dev/null; do
        sleep 10
        if [ "$ALDAAS_MODE" = "external" ]; then
            # External mode: check if Argo workflow still exists
            if ! argo get "$aldaas_full" >/dev/null 2>&1; then
                FAIL_COUNT=$((FAIL_COUNT + 1))
                echo "Argo workflow gone ($FAIL_COUNT/$FAIL_THRESHOLD) for $aldaas_full"
            else
                FAIL_COUNT=0
            fi
        else
            # Internal mode: check Service DNS
            if ! nslookup "$aldaas_name.$ALDAAS_NAMESPACE.svc.cluster.local" >/dev/null 2>&1; then
                FAIL_COUNT=$((FAIL_COUNT + 1))
                echo "DNS lookup failed ($FAIL_COUNT/$FAIL_THRESHOLD) for $aldaas_name.$ALDAAS_NAMESPACE.svc.cluster.local"
            else
                FAIL_COUNT=0
            fi
        fi
        if [ "$FAIL_COUNT" -ge "$FAIL_THRESHOLD" ]; then
            echo "Upstream gone after $FAIL_THRESHOLD consecutive failures — re-provisioning"
            kill $TUNNEL_PID 2>/dev/null
            wait $TUNNEL_PID 2>/dev/null
            break
        fi
    done

    # Backoff before retry
    sleep $BACKOFF
    BACKOFF=$((BACKOFF * 2))
    [ $BACKOFF -gt $MAX_BACKOFF ] && BACKOFF=$MAX_BACKOFF
done