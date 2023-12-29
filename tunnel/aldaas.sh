#!/bin/sh
ALDAAS_PROTOCOL="${ALDAAS_PROTOCOL:-ws}"
ALDAAS_SERVER="${ALDAAS_SERVER:-$ARGO_SERVER}"
ALDAAS_PORT="${ALDAAS_PORT:-5432}"

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
    aldaas_name=`argo submit --from workflowtemplate/$ALDAAS_NAME -o name`
    argo watch $aldaas_name
    echo $aldaas_name > $FILE
fi

tcp-over-websocket  client -listen_tcp 0.0.0.0:$ALDAAS_PORT -connect_ws "$ALDAAS_PROTOCOL://$ALDAAS_SERVER/$ALDAAS_NAME/$ALDAAS_TOKEN/$aldaas_name"