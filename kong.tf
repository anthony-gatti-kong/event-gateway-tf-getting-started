resource "konnect_event_gateway" "event_gateway_terraform" {
    provider = konnect-beta
    name     = "event_gateway_terraform"
}

// Backend cluster configuration - local
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

// Virtual cluster configuration
resource "konnect_event_gateway_virtual_cluster" "virtual_cluster" {
    provider = konnect-beta
    name = "virtual_cluster"
    description = "terraform virtual cluster"
    gateway_id = konnect_event_gateway.event_gateway_terraform.id

    destination = {
      id = konnect_event_gateway_backend_cluster.backend_cluster.id
    }

    // acl_mode = "passthrough"
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

    authentication = [ {
      sasl_plain = {
        mediation = "terminate"
        principals = [
          { username = "user1", password = "$${env['USER1_PASSWORD']}" },
          { username = "user2", password = "$${env['USER2_PASSWORD']}" }
        ]
      }
    } ]

    /* Not used yet in demo
    authentication = [ {
      oauth_bearer = {
        mediation = "terminate"
        jwks = {
          endpoint = "http://localhost:8080/realms/kafka-realm/protocol/openid-connect/certs"
          timeout = "1s"
        }
      }
    } ]
    */
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
                    { name = "describe" }
                ]
                resource_type = "topic"
                resource_names = [{
                    match = "*"
                }]
            },{
                action = "allow"
                operations = [
                    { name = "write" }
                ]
                resource_type = "topic"
                resource_names = [{
                    match = "*"
                }
                ]
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

// Add skip record policy on orders topic
resource "konnect_event_gateway_consume_policy_skip_record" "skip_record" {
    provider = konnect-beta
    name = "skip_records"
    description = "skip records"
    gateway_id = konnect_event_gateway.event_gateway_terraform.id
    virtual_cluster_id = konnect_event_gateway_virtual_cluster.virtual_cluster.id

    condition = "context.auth.principal.name == 'user2' && record.headers['my-header'] == 'value'"
}

// Listener configuration
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

// Second virtual cluster
resource "konnect_event_gateway_virtual_cluster" "virtual_cluster2" {
    provider = konnect-beta
    name = "virtual_cluster_teamb"
    description = "terraform virtual cluster"
    gateway_id = konnect_event_gateway.event_gateway_terraform.id

    destination = {
      id = konnect_event_gateway_backend_cluster.backend_cluster.id
    }

    // acl_mode = "passthrough"
    acl_mode = "passthrough"
    dns_label = "vcluster-2"

    namespace = {
      prefix = "team2-"
      mode = "hide_prefix"
    }

    authentication = [ {
      sasl_plain = {
        mediation = "terminate"
        principals = [
          { username = "user3", password = "$${env['USER3_PASSWORD']}" },
        ]
      }
    } ]
}

resource "konnect_event_gateway_listener" "listener_teamb" {
    provider = konnect-beta
    name = "konnect_listener2"
    description = "terraform listener"
    gateway_id = konnect_event_gateway.event_gateway_terraform.id

    addresses = ["0.0.0.0"]
    ports = ["19102-19112"]
}

resource "konnect_event_gateway_listener_policy_forward_to_virtual_cluster" "forward_to_vcluster_teamb" {
    provider = konnect-beta
    name = "forward_to_vcluster2"
    description = "forward to vcluster policy"
    gateway_id = konnect_event_gateway.event_gateway_terraform.id
    event_gateway_listener_id = konnect_event_gateway_listener.listener_teamb.id

    config = {
        port_mapping = {
            advertised_host = "localhost"
            destination = {
                virtual_cluster_reference_by_id = {
                    id = konnect_event_gateway_virtual_cluster.virtual_cluster2.id
                }
            }
        }
    }
}
