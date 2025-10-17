resource "konnect_event_gateway" "event_gateway_terraform" {
    provider = konnect-beta
    name     = "event_gateway_terraform"
}

/* For real demo - use MSK cluster
resource "konnect_event_gateway_backend_cluster" "backend_cluster" {
    provider = konnect-beta
    name = "backend_cluster"
    description = "terraform cluster"
    gateway_id = konnect_event_gateway.event_gateway_terraform.id

    authentication = {
        sasl_scram = {
            algorithm = "sha512"
            username  = "username"
            password  = "$${env['KAFKA_PASSWORD']}"
        }
    }

    bootstrap_servers = [
        "b-1.xxx.kafka.us-west-2.amazonaws.com:9096",
        "b-2.xxx.kafka.us-west-2.amazonaws.com:9096",
        "b-3.xxx.kafka.us-west-2.amazonaws.com:9096",
    ]

    tls = {
        enabled = false
    }

    insecure_allow_anonymous_virtual_cluster_auth = true
}
*/

resource "konnect_event_gateway_backend_cluster" "backend_cluster" {
    provider = konnect-beta
    name = "backend_cluster"
    description = "terraform cluster"
    gateway_id = konnect_event_gateway.event_gateway_terraform.id

    authentication = {
        anonymous = {}
    }

    bootstrap_servers = [
        "kafka1:9092",
        "kafka2:9092",
        "kafka3:9092"
    ]

    tls = {
        enabled = false
    }

    insecure_allow_anonymous_virtual_cluster_auth = true
}

resource "konnect_event_gateway_virtual_cluster" "virtual_cluster" {
    provider = konnect-beta
    name = "virtual_cluster"
    description = "terraform virtual cluster"
    gateway_id = konnect_event_gateway.event_gateway_terraform.id

    destination = {
      id = konnect_event_gateway_backend_cluster.backend_cluster.id
    }

    acl_mode = "enforce_on_gateway"
    dns_label = "vcluster-1"

    namespace = {
      prefix = "team1-"
      mode = "hide_prefix"
      additional = {
        consumer_groups = [{}]
        topics = [ {
          exact_list = {
            conflict = "warn"
            exact_list = [{
              backend = "extra-topic"
            }]
          }
        } ]
      }
    }

    /* For real demo - use MSK with SCRAM
    authentication = [ {
      sasl_scram = {
        algorithm = "sha512"
      }
    } ]
    */

    authentication = [ {
      sasl_plain = {
        mediation = "terminate"
        principals = [
          { username = "user1", password = "$${env['USER1_PASSWORD']}" },
          { username = "user2", password = "$${env['USER2_PASSWORD']}" }
        ]
      }
    } ]
}

// Add ACL policy for user1
resource "konnect_event_gateway_cluster_policy_acls" "acl_topic_policy_u1" {
    provider = konnect-beta
    name = "acl_topic_policy1"
    description = "ACL policy for ensuring access to topics based on principals"
    gateway_id = konnect_event_gateway.event_gateway_terraform.id
    virtual_cluster_id = konnect_event_gateway_virtual_cluster.virtual_cluster.id

    condition = "context.auth.principal.name == 'user1'"
    config = {
        rules = [
            {
                action = "allow"
                operations = [
                    { name = "describe" },
                    { name = "read" },
                    { name = "write" }
                ]
                resource_type = "topic"
                resource_names = [{
                    match = "*"
                }]
            }
        ]
    }
}

// Add ACL policy for user2
resource "konnect_event_gateway_cluster_policy_acls" "acl_topic_policy_u2" {
    provider = konnect-beta
    name = "acl_topic_policy2"
    description = "ACL policy for ensuring access to topics based on principals"
    gateway_id = konnect_event_gateway.event_gateway_terraform.id
    virtual_cluster_id = konnect_event_gateway_virtual_cluster.virtual_cluster.id

    condition = "context.auth.principal.name == 'user2'"
    config = {
        rules = [
            {
                action = "allow"
                operations = [
                    { name = "describe" }
                ]
                resource_type = "topic"
                resource_names = [{
                    match = "orders"
                },{
                    match = "parts"
                },{
                    match = "extra-topic"
                }]
            },{
                action = "allow"
                operations = [
                    { name = "read" }
                ]
                resource_type = "topic"
                resource_names = [{
                    match = "orders"
                }]
            }
        ]
    }
}

// Add skip record policy on orders topic based on header & principal
resource "konnect_event_gateway_consume_policy_skip_record" "skip_record" {
    provider = konnect-beta
    name = "skip_records"
    description = "skip records"
    gateway_id = konnect_event_gateway.event_gateway_terraform.id
    virtual_cluster_id = konnect_event_gateway_virtual_cluster.virtual_cluster.id

    condition = "record.headers['sandbox'] == '1' && context.auth.principal.name != 'user1'"
}

// Add skip record policy within a payload by marshaling it on consume.
resource "konnect_event_gateway_consume_policy_schema_validation" "schema_val" {
    provider = konnect-beta
    name = "schema-val"
    description = "serialize for record parsing"
    gateway_id = konnect_event_gateway.event_gateway_terraform.id
    virtual_cluster_id = konnect_event_gateway_virtual_cluster.virtual_cluster.id
    depends_on = [ konnect_event_gateway_consume_policy_skip_record.skip_record ]
    
    config = {
        type = "json"
        value_validation_action = "mark"
    }
}

// Add skip record policy on records based on record conten
resource "konnect_event_gateway_consume_policy_skip_record" "skip_record_val" {
    provider = konnect-beta
    name = "skip_records_2"
    description = "skip records"
    gateway_id = konnect_event_gateway.event_gateway_terraform.id
    virtual_cluster_id = konnect_event_gateway_virtual_cluster.virtual_cluster.id
    depends_on = [ konnect_event_gateway_consume_policy_schema_validation.schema_val ]

    parent_policy_id = konnect_event_gateway_consume_policy_schema_validation.schema_val.id
    condition = "record.value.content['name'] == 'pii_value'"
}

resource "konnect_event_gateway_listener" "listener" {
    provider = konnect-beta
    name = "konnect_listener"
    description = "terraform listener"
    gateway_id = konnect_event_gateway.event_gateway_terraform.id

    addresses = ["0.0.0.0"]
    ports = ["19092-19101"]
}

resource "konnect_event_gateway_listener_policy_forward_to_virtual_cluster" "forward_to_vcluster" {
    provider = konnect-beta
    name = "forward_to_vcluster"
    description = "forward to vcluster policy"
    gateway_id = konnect_event_gateway.event_gateway_terraform.id
    event_gateway_listener_id = konnect_event_gateway_listener.listener.id

    config = {
        port_mapping = {
            advertised_host = "localhost"
            destination = {
                virtual_cluster_reference_by_id = {
                    id = konnect_event_gateway_virtual_cluster.virtual_cluster.id
                }
            }
        }
    }
}

