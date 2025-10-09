resource "konnect_event_gateway" "event_gateway_terraform" {
    provider = konnect-beta
    name     = "event_gateway_terraform"
}

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

    acl_mode = "passthrough"
    dns_label = "vcluster-1"

    authentication = [ {
      anonymous = {}
    } ]
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

