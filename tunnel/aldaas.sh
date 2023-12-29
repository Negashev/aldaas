#!/bin/sh
ALDAAS_NAMESPACE=aldaas
ALDAAS_AWT=aldaas-chart

argo -n $ALDAAS_NAMESPACE submit --from workflowtemplate/$ALDAAS_AWT --watch