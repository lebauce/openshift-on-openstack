#!/bin/bash

[ -z "$os_auth_url" -o -z "$os_username" -o -z "$os_password" -o -z "$os_tenant_name" ] && exit 0

controller_ip=$(echo $os_auth_url | cut -f 3 -d "/" | cut -f 1 -d ":")
memory=$(cat /proc/meminfo | grep "MemTotal:" | cut -d : -f 2 | tr -d ' ' | tr -d 'kB')
pods=$(oc get pods --show-labels=false --no-headers=true | grep Running | wc -l)
nodes=$(oc get nodes --show-labels=false --no-headers=true | grep Ready | wc -l)
let "pods_per_node=$memory/512000"
let "result=$pods*100/$nodes/$pods_per_node"
curl http://$controller_ip:35357/v2.0/tokens -X POST -H "Content-Type: application/json" -d "{\"auth\": {\"tenantName\": \"$os_tenant_name\", \"passwordCredentials\": {\"username\": \"$os_username\", \"password\": \"$os_password\"}}}" > /tmp/auth_token.dat
token=$(awk -F"[,:]" '{for(i=1;i<=NF;i++)
                       {if($i~/id\042/)
                        {print $(i+1)}
                       }
                      }' /tmp/auth_token.dat | awk -F'"' '{print $2; exit}')
curl -X POST -H "X-Auth-Token: $token" -H 'Content-Type: application/json' -d '[{"counter_name": "pods", "user_id": "1",  "resource_id": "1","counter_unit": "%", "counter_volume":'"$result"', "project_id": "1", "counter_type": "gauge"}]' http://$controller_ip:8777/v2/meters/pods
rm /tmp/auth_token.dat