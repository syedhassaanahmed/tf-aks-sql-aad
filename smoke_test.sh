#!/bin/bash

POD_NAME="sql-aad-test-$(uuidgen | head -c 8)"

az aks get-credentials -g $rg_name -n $aks_cluster_name --overwrite-existing

PS_SCRIPT=$(cat test-sql-aad.ps1)

kubectl run --generator=run-pod/v1 -i $POD_NAME \
  --image=mcr.microsoft.com/powershell \
  --labels="aadpodidbinding=$aad_pod_id_binding_selector" \
  --env="server=$sql_server_fqdn" \
  --env="database=$sql_db_name" \
  --restart=Never \
  -- pwsh -c "$PS_SCRIPT"

kubectl delete pod $POD_NAME
