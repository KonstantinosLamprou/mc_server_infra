variable "tenancy_ocid" {
  type = string
}

variable "user_ocid" {
  type = string
}

variable "fingerprint" {
  type = string
}

variable "private_key" {
  type      = string
  sensitive = true
}

variable "region" {
  type    = string
  default = "eu-frankfurt-1"
}

variable "ssh_public_key" {
  type        = string
  description = "Inhalt der .pub-Datei"
}

variable "ocpus" {
  type    = number
  default = 2
}

variable "memory_gb" {
  type    = number
  default = 12
}

variable "ad_index" {
  type        = number
  default     = 0
  description = "Availability Domain (0, 1 oder 2). Bei 'Out of capacity' einen anderen Wert probieren."
}