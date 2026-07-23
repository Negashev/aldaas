#!/bin/sh
ALDAAS_PORT="${ALDAAS_PORT:-5432}"
ALDAAS_TTL="${ALDAAS_TTL:-300}"
# Internal Service DNS suffix for direct WebSocket connection (bypasses ALB 60s idle timeout)
# The WorkflowTemplate creates a Service named {{workflow.name}} in this namespace
# with port 8080 (tunnel) + 5432 (postgres)
ALDAAS_NAMESPACE="${ALDAAS_NAMESPACE:-aldaas}"

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
    aldaas_name=`argo submit --from workflowtemplate/$ALDAAS_NAME -p ttl=$ALDAAS_TTL -o name`
    argo watch $aldaas_name
    echo $aldaas_name > $FILE
fi

nohup sh -c "while true; do curl --connect-timeout 3600 -vv telnet://0.0.0.0:$ALDAAS_PORT; sleep 0.1; done" > /dev/null 2>&1 &

# Connect directly to the internal Service DNS (ws://, not wss://)
# Bypasses AWS ALB 60s idle timeout that kills WebSocket connections
# Service: <workflow-name>.<namespace>.svc.cluster.local:8080 (tunnel port)
tcp-over-websocket  client -listen_tcp 0.0.0.0:$ALDAAS_PORT -connect_ws "ws://$aldaas_name.$ALDAAS_NAMESPACE.svc.cluster.local:8080"