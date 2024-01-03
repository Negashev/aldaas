#!/bin/sh
ALDAAS_PROTOCOL="${ALDAAS_PROTOCOL:-wss}"
ALDAAS_SERVER="${ALDAAS_SERVER:-$ARGO_SERVER}"
ALDAAS_PORT="${ALDAAS_PORT:-5432}"
ALDAAS_TTL="${ALDAAS_TTL:-300}"

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

tcp-over-websocket  client -listen_tcp 0.0.0.0:$ALDAAS_PORT -connect_ws "$ALDAAS_PROTOCOL://$ALDAAS_SERVER/$ALDAAS_NAME/$ALDAAS_TOKEN/$aldaas_name"