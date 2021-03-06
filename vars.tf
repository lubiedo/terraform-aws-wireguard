variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Which AWS Region to spin the instance on."
}

variable "client_ip" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Accept connections only from this client IP (default: any)"

  validation {
    condition     = can(regex("^(?:([0-9]{1,3}\\.){3})[0-9]{1,3}/[0-9]{1,2}$", var.client_ip))
    error_message = "Variable `client_ip` must be a valid CIDR block (a.b.c.d/range)."
  }
}

variable "wgclient" {
  type        = string
  description = "Client's public key generated by WireGuard to be added as a peer."
}
