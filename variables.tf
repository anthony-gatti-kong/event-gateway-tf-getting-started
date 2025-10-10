variable "konnect_server_url" {
    type        = string
    description = "Which Konnect instance to point at"
    default     = "https://us.api.konghq.com"
}

variable "konnect_api_token" {
    type        = string
    description = "API token to reach Konnect"
    default     = null
    sensitive   = true
}