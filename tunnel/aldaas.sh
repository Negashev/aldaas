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

aldaas_name=""
# check save
FILE=/tmp/aldaas
if [ -f "$FILE" ]; then
    echo "save file exists."
    aldaas_name=`cat $FILE`
    # check wf exist
    if ! argo get $aldaas_name; then
        aldaas_name=""
        echo "Not found $aldaas_name"
    else
        echo "Use saved $aldaas_name"
    fi
fi

# if no save create new aldaas wf
if [[ -z $aldaas_name ]]; then
    # argo submit -o name returns "namespace/workflow-name" (e.g. "aldaas/aldaas-dandelion-app-backend-w9xc5")
    # We need just the workflow-name part for Service DNS / ingress path
    aldaas_full=`argo submit --from workflowtemplate/$ALDAAS_NAME -p ttl=$ALDAAS_TTL -o name`
    # Strip namespace prefix: "aldaas/wf-name" → "wf-name"
    aldaas_name=`echo "$aldaas_full" | sed 's|^.*/||'`
    echo "$aldaas_full" > $FILE
fi

# Wait for the ephemeral DB Service to become available (port 5432)
# Do NOT use `argo watch` — it blocks until the ENTIRE workflow completes,
# including cleanup-pvc (sleep 3600 = 1 hour). We only need to wait until
# the Service is reachable, which happens after wait-service step succeeds.
echo "Waiting for ephemeral DB Service $aldaas_name.$ALDAAS_NAMESPACE.svc.cluster.local:5432..."
for i in $(seq 1 120); do
    if nc -z "$aldaas_name.$ALDAAS_NAMESPACE.svc.cluster.local" 5432 2>/dev/null; then
        echo "DB Service is ready (attempt $i)"
        break
    fi
    if [ "$i" -eq 120 ]; then
        echo "ERROR: DB Service did not become available within 120 seconds"
        exit 1
    fi
    sleep 1
done

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

tcp-over-websocket  client -listen_tcp 0.0.0.0:$ALDAAS_PORT -connect_ws "$WS_URL"