#!/bin/bash

IS_LEADER=$(curl -s -k https://127.0.0.1:8200/v1/sys/leader| jq .is_self)

if [[ "$IS_LEADER" == "true" ]]
then
  curl -s -k -X PUT -H "X-Vault-Request: true" -H "X-Vault-Token: $VAULT_TOKEN" https://127.0.0.1:8200/v1/sys/step-down
fi
