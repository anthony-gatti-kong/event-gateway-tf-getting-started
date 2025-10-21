# Getting started

To use this provider, first export your personal access token from Konnect like so:

```shell
export TF_VAR_konnect_api_token=kpat_<your-personal-access-token>
```

Then run `terraform init` and `terraform plan`.

# Demo flow

Note that the `-b` on the consume command shows all messages in the topic, omit if not needed for the specific flow.

## ACLs

1. Set up cluster with topics: `['team1-orders', 'team1-parts', 'team2-orders', 'team2-parts', 'extra-topic']`
```shell
# With delete if needed
kafkactl --context backend delete topic team1-orders team2-orders team1-parts team2-parts extra-topic
kafkactl --context backend create topic team1-orders team2-orders team1-parts team2-parts extra-topic
```

2. Show backend cluster with topics both inside and outside of the namespace.
```shell
kafkactl --context backend list topics
```

3. Create virtual cluster with SASL/SCRAM authentication but no ACLs. Include namespace.

4. Set virtual cluster `acl_mode` to `passthrough`. Show topics on the backend cluster. (To do this, the ACL policies must be commented out and removed.)
```shell
kafkactl --context user1 list topics
```

5. Flip `acl_mode` to `enforce_on_gateway`. Show no topics existing.
```shell
kafkactl --context user1 list topics
```

6. Add ACL policy to allow user `user1` to list a subset of topics. Set `user2` to list a different subset but not write to them. (These ACLs also include write and read for the next step.) Show the difference in topics listed.
```shell
kafkactl --context user1 list topics
kafkactl --context user2 list topics
```

7. Show `user1` can produce to the orders topic successfully. Show `user2` can also read from that topic, but not write to it.
```shell
kafkactl --context user1 produce orders --value="{'customer':'acme','sku':123}"
kafkactl --context user2 consume orders -b
kafkactl --context user2 produce orders --value="{'customer':'acme','sku':123}"
```
The last command should fail.

8. Show `user1` cannot produce to the parts topic.
```shell
kafkactl --context user1 produce parts --value="{'id':1,'name':'compactor'}"
```

9. Quickly give `user1` write access to the parts topic via uncomment.
```shell
kafkactl --context user1 produce parts --value="{'id':1,'name':'compactor'}"
```

## Record filtering

1. Show configuration: `user1` can see sandbox records, but `user2` cannot. Sandbox is indicated via a `sandbox:1` header on the produce command.

Terminal 0:
```shell
kafkactl --context backend produce team1-orders --value='{"id":1,"name":"test"}' --header sandbox:1
```

Terminal 1:
```shell
kafkactl --context user1 consume orders -b
```

Terminal 2:
```shell
kafkactl --context user2 consume orders -b
```
`user1` should see the record; `user2` should not.

2. Show configuration: `user1` can see records with value `name=test` but not with `name=pii_value`. Rerun the first produce command above.

Terminal 0:
```shell
kafkactl --context backend produce team1-orders --value='{"id":1,"name":"test"}' --header sandbox:1
kafkactl --context backend produce team1-orders --value='{"id":1,"name":"pii_value"}' --header sandbox:1
kafkactl --context backend produce team1-orders --value='{"id":1,"name":"pii_other"}' --header sandbox:1

```

Terminal 1:
```shell
kafkactl --context user1 consume -b
```

The first record should come through, the second should not.

# Curl commands to set up data plane

1. Reset the environment variables for the account.
```shell
export KONNECT_API_TOKEN=${TF_VAR_konnect_api_token}
export KONNECT_URL="https://us.api.konghq.com"
```

2. Create control plane.
```shell
curl --request POST \
        --url  "${KONNECT_URL}/v1/event-gateways" \
        --header "Accept: application/json, application/problem+json" \
        --header "Authorization: Bearer ${KONNECT_API_TOKEN}" \
        --header "Content-Type: application/json" \
        --data '{
            "name": "konnect_api_cp"  
        }'
```
This will return the control plane ID.

3. Export the control plane ID.
```shell
export KONNECT_CP_ID=<cp-id>
```

4. Create backend cluster.
```shell
curl --request POST \
  --url "${KONNECT_URL}/v1/event-gateways/${KONNECT_CP_ID}/backend-clusters" \
  --header 'Accept: application/json, application/problem+json' \
  --header "Authorization: Bearer ${KONNECT_API_TOKEN}" \
  --header 'Content-Type: application/json' \
  --data '{
        "name": "new-backend-cluster",
        "authentication": {
            "type": "sasl_scram",
            "algorithm": "sha512",
            "username": "my-username",
            "password": "'${env["KAFKA_PASSWORD"]}'"
        },
        "bootstrap_servers": [ 
            "kafka1:9092",
            "kafka2:9092",
            "kafka3:9092"
        ],
        "tls": {
            "enabled": false
        }
    }'
```
This will return the backend cluster ID.

5. Set backend cluster ID.
```shell
export KONNECT_BC_ID=<cluster-id>
```

6. Create virtual cluster.
```shell
curl --request POST \
  --url "${KONNECT_URL}/v1/event-gateways/${KONNECT_CP_ID}/virtual-clusters" \
  --header 'Accept: application/json, application/problem+json' \
  --header "Authorization: Bearer ${KONNECT_API_TOKEN}" \
  --header 'Content-Type: application/json' \
  --data '{
        "name": "my-virtual-cluster",
        "destination": {
            "id": "'${KONNECT_BC_ID}'"
        },
        "authentication": [
            {
                "type": "sasl_scram",
                "algorithm": "sha512"
            }
        ],
        "acl_mode": "enforce_on_gateway",
        "dns_label": "vcluster-1"
    }'
```
This will return the virtual cluster ID.

7. Set virtual cluster ID.
```shell
export KONNECT_VC_ID=<vc-id>
```

8. Add listener to virtual cluster.
```shell
curl --request POST \
    --url "${KONNECT_URL}/v1/event-gateways/${KONNECT_CP_ID}/listeners" \
    --header 'Accept: application/json, application/problem+json' \
    --header "Authorization: Bearer ${KONNECT_API_TOKEN}" \
    --header 'Content-Type: application/json' \
    --data '{
        "name": "my-listener",
        "addresses": [
            "0.0.0.0"
        ],
        "ports": [
            "19092-19101"
        ]
    }'
```
This will return the listener ID.

9. Set the listener ID.
```shell
export KONNECT_LISTENER_ID=<listener-id>
```

10. Create a forward-to-vc policy on the listener.
```shell
curl --request POST \
    --url "${KONNECT_URL}/v1/event-gateways/${KONNECT_CP_ID}/listeners/${KONNECT_LISTENER_ID}/policies" \
    --header 'Accept: application/json, application/problem+json' \
    --header "Authorization: Bearer ${KONNECT_API_TOKEN}" \
    --header 'Content-Type: application/json' \
    --data '{
        "type": "forward_to_virtual_cluster",
        "name": "forward-policy",
        "config": {
            "type": "port_mapping",
            "bootstrap_port": "at_start",
            "advertised_host": "localhost",
            "destination": {
                "id": "'${KONNECT_VC_ID}'"
            }
        }
    }'
```

11. Add ACL policy 1 on virtual cluster.
```shell
curl --request POST \
  --url "${KONNECT_URL}/v1/event-gateways/${KONNECT_CP_ID}/virtual-clusters/${KONNECT_VC_ID}/cluster-policies" \
  --header 'Accept: application/json, application/problem+json' \
  --header "Authorization: Bearer ${KONNECT_API_TOKEN}" \
  --header 'Content-Type: application/json' \
  --data '{
        "type": "acls",
        "name": "acl_policy_1",
        "condition": "context.auth.principal.name == \"user1\"",
        "config": {
            "rules": [
                {
                "resource_type": "topic",
                "resource_names": [
                    {
                        "match": "*"
                    }
                ],
                "operations": [
                    {
                        "name": "describe"
                    }
                ],
                    "action": "allow"
                },
                {
                "resource_type": "topic",
                "resource_names": [
                    {
                        "match": "orders"
                    },
                    {
                        "match": "parts"
                    }
                ],
                "operations": [
                    {
                        "name": "write"
                    }
                ],
                    "action": "allow"
                }
            ]
        }
    }'
```

12. Add ACL policy 2 on virtual cluster.
```shell
curl --request POST \
  --url "${KONNECT_URL}/v1/event-gateways/${KONNECT_CP_ID}/virtual-clusters/${KONNECT_VC_ID}/cluster-policies" \
  --header 'Accept: application/json, application/problem+json' \
  --header "Authorization: Bearer ${KONNECT_API_TOKEN}" \
  --header 'Content-Type: application/json' \
  --data '{
        "type": "acls",
        "name": "acl_policy_2",
        "condition": "context.auth.principal.name == \"user2\"",
        "config": {
            "rules": [
                {
                "resource_type": "topic",
                "resource_names": [
                    {
                        "match": "orders"
                    },
                    {
                        "match": "parts"
                    }
                ],
                "operations": [
                    {
                        "name": "describe"
                    }
                ],
                    "action": "allow"
                },
                {
                "resource_type": "topic",
                "resource_names": [
                    {
                        "match": "orders"
                    }
                ],
                "operations": [
                    {
                        "name": "read"
                    }
                ],
                    "action": "allow"
                }
            ]
        }
    }'
```

13. Add a skip record policy referencing record header on consume phase.
```shell
curl --request POST \
  --url "${KONNECT_URL}/v1/event-gateways/${KONNECT_CP_ID}/virtual-clusters/${KONNECT_VC_ID}/consume-policies" \
  --header 'Accept: application/json, application/problem+json' \
  --header "Authorization: Bearer ${KONNECT_API_TOKEN}" \
  --header 'Content-Type: application/json' \
  --data '{
        "type": "skip_record",
        "name": "Skip record policy based on header",
        "description": "Skip records when header contains specific value",
        "condition": "record.headers[\"sandbox\"] == \"1\" && context.auth.principal.name != \"user1\""
  }'
```

14. Add schema validation policy for marshaling record for field-level filtering.
```shell
curl --request POST \
  --url "${KONNECT_URL}/v1/event-gateways/${KONNECT_CP_ID}/virtual-clusters/${KONNECT_VC_ID}/consume-policies" \
  --header 'Accept: application/json, application/problem+json' \
  --header "Authorization: Bearer ${KONNECT_API_TOKEN}" \
  --header 'Content-Type: application/json' \
  --data '{
        "type": "schema_validation",
        "name": "Consume schema validation 2",
        "description": "Serialize records for record-level filtering",
        "config": {
            "type": "json",
            "value_validation_action": "mark"
        }
  }'
```
This will output the policy ID, which is used in the next step to add a nested policy acting on the records.

15. Set the parent policy ID.
```shell
export KONNECT_PARENT_POLICY_ID=<schema-validation-policy-id>
```

16. Add field level filtering.
```shell
curl --request POST \
  --url "${KONNECT_URL}/v1/event-gateways/${KONNECT_CP_ID}/virtual-clusters/${KONNECT_VC_ID}/consume-policies?parent_policy_id=${KONNECT_PARENT_POLICY_ID}" \
  --header 'Accept: application/json, application/problem+json' \
  --header "Authorization: Bearer ${KONNECT_API_TOKEN}" \
  --header 'Content-Type: application/json' \
  --data '{
        "type": "skip_record",
        "name": "Skip record policy based on record content",
        "description": "Skip records when record field contains specific value",
        "condition": "record.value.content[\"name\"].startsWith(\"pii\")"
  }'
```
Note the string matching options here are:
- `startsWith()`
- `endsWith()`
- `substring()`
- `includes()`
- `length`
