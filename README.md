# Getting started

To use this provider, first export your personal access token from Konnect like so:

```{shell}
export TF_VAR_konnect_api_token=kpat_<your-personal-access-token>
```

Then run `terraform init` and `terraform plan`.

# Demo flow

## ACLs

1. Set up cluster with topics: `['team1-orders', 'team1-parts', 'team2-orders', 'team2-parts', 'extra-topic']`
```{shell}
# With delete if needed
kafkactl --context backend delete topic team1-orders team2-orders team1-parts team2-parts extra-topic
kafkactl --context backend create topic team1-orders team2-orders team1-parts team2-parts extra-topic
```

2. Show backend cluster with topics both inside and outside of the namespace.
```{shell}
kafkactl --context backend list topics
```

3. Create virtual cluster with SASL/SCRAM authentication but no ACLs. Include namespace.

4. Set virtual cluster `acl_mode` to `passthrough`. Show topics on the backend cluster. (To do this, the ACL policies must be commented out and removed.)
```{shell}
kafkactl --context user1 list topics
```

5. Flip `acl_mode` to `enforce_on_gateway`. Show no topics existing.
```{shell}
kafkactl --context user1 list topics
```

6. Add ACL policy to allow user `user1` to list a subset of topics. Set `user2` to list a different subset but not write to them. (These ACLs also include write and read for the next step.) Show the difference in topics listed.
```{shell}
kafkactl --context user1 list topics
kafkactl --context user2 list topics
```

7. Show `user1` can produce to the orders topic successfully. Show `user2` can also read from that topic, but not write to it.
```{shell}
kafkactl --context user1 produce orders --value="{'customer'='acme','sku'=123}"
kafkactl --context user2 consume orders
kafkactl --context user2 produce orders --value="{'customer'='acme','sku'=123}"
```

8. Show `user1` cannot produce to the parts topic.
```{shell}
kafkactl --context user1 produce parts --value="{'id'=1,'name'='compactor'}"
```

9. Quickly give `user1` write access to the parts topic via uncomment.
```{shell}
kafkactl --context user1 produce parts --value="{'id'=1,'name'='compactor'}"
```

# Curl commands to set up data plane

1. Reset the environment variables for the account.
```{shell}
export KONNECT_API_TOKEN=${TF_VAR_konnect_api_token}
export KONNECT_URL="https://us.api.konghq.com"
```

2. Create control plane.
```{shell}
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
```{shell}
export KONNECT_CP_ID=<cp-id>
```

4. Create backend cluster.
```{shell}
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


