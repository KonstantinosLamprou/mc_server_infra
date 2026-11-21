terraform {
  required_version = ">= 1.6"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket = "tfstate-minecraft"
    key    = "minecraft/terraform.tfstate"
    region = "eu-frankfurt-1"

    use_path_style              = true
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}

provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
  fingerprint  = var.fingerprint
  private_key  = var.private_key
  region       = var.region
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.tenancy_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_vcn" "main" {
  compartment_id = var.tenancy_ocid
  display_name   = "minecraft-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "minecraft-igw"
  enabled        = true
}

resource "oci_core_route_table" "public" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "minecraft-public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

resource "oci_core_security_list" "mc" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "minecraft-sl"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    description = "SSH (nur per Key)"
    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    description = "Minecraft Java"
    tcp_options {
      min = 25565
      max = 25565
    }
  }

  ingress_security_rules {
    protocol    = "17" # UDP
    source      = "0.0.0.0/0"
    description = "Minecraft Bedrock (Geyser)"
    udp_options {
      min = 19132
      max = 19132
    }
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = var.tenancy_ocid
  vcn_id                     = oci_core_vcn.main.id
  display_name               = "minecraft-public"
  cidr_block                 = "10.0.1.0/24"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.mc.id]
  prohibit_public_ip_on_vnic = false
}

locals {
  cloud_init = templatefile("${path.module}/cloud-init.yaml", {
    compose_b64 = base64encode(file("${path.module}/../docker/docker-compose.yml"))
  })
}

resource "oci_core_instance" "mc" {
  compartment_id      = var.tenancy_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.ad_index].name
  display_name        = "minecraft"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_gb
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = 100
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(local.cloud_init)
  }

  lifecycle {
    ignore_changes = [metadata, source_details[0].source_id]
  }
}