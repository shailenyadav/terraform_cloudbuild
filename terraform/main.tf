#Main
#VPC:
# VPC: Create a Google Cloud VPC (Virtual Private Cloud)
resource "google_compute_network" "ncorium-default" {
  name                    = "ncorium-network"
  auto_create_subnetworks = false
}

#Subnet:
# Subnet: Create a subnet in the VPC
resource "google_compute_subnetwork" "ncorium-default" {
  name          = "ncorium-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.ncorium-default.id
}

#Firewalls:
# Target HTTP Proxy: Configure an HTTP proxy to handle incoming traffic from clients on your behalf
resource "google_compute_firewall" "allow_http" {
  name    = "allow-http-rule"
  network = google_compute_network.ncorium-default.id

  allow {
    protocol = "icmp"
  }

  allow {
    ports    = ["80","22"]
    protocol = "tcp"
  }
  # Allow incoming traffic from IAP for TCP hostname
  source_ranges = ["35.235.240.0/20"]
  target_tags = ["allow-health-check"]
  priority    = 1000
}

# Target HTTPS Proxy: Configure an HTTPS proxy to handle incoming traffic from clients on your behalf
resource "google_compute_firewall" "allow_https" {
  name    = "allow-https-rule"
  network = google_compute_network.ncorium-default.id

  allow {
    ports    = ["443"]
    protocol = "tcp"
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags = ["allow-health-check"]
  priority    = 1000
}

#NAT:
#Net Router
resource "google_compute_router" "router" {
  name    = "ncorium-router"
  region  = google_compute_subnetwork.ncorium-default.region
  network = google_compute_network.ncorium-default.id
  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "nat" {
  name                               = "ncorium-router-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

#Instance Template:
# Instance Template: Create an instance template for VM instances
resource "google_compute_instance_template" "ncorium-default" {
  name         = "ncorium-mig-template"
  machine_type = "e2-standard-2"   # 4 vCPU + 16 GB memory
  tags         = ["allow-health-check"]

  network_interface {
    network    = google_compute_network.ncorium-default.id
    subnetwork = google_compute_subnetwork.ncorium-default.id
  }
  
  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2004-lts"   # Change the source image to Ubuntu 20.04 LTS
    auto_delete  = true
    boot         = true
  }

  # install nginx and serve a simple web page
  metadata = {
    startup-script = <<-EOF1
      #! /bin/bash
      sudo apt update && sudo apt upgrade 
      sudo apt install -y apache2 
      sudo service apache2 restart
    EOF1
  }
  lifecycle {
    prevent_destroy = false  # Disable deletion protection for the instance created from this template
  }
}

#MIG (Managed Instance Group):
# Instance Group Manager (MIG): Create an instance group manager for VM instances
resource "google_compute_instance_group_manager" "ncorium-default" {
  name = "ncorium-mig"
  zone = var.zone
  named_port {
    name = "http"
    port = 80
  }
  version {
    instance_template = google_compute_instance_template.ncorium-default.id
    name              = "primary"
  }
  base_instance_name = "ncorium-vm"
  target_size        = 1

  named_port {
    name = "custom-http"
    port = 80
  }

  auto_healing_policies {
    health_check      = "${google_compute_health_check.autohealing.self_link}"
    initial_delay_sec = 60
  }
}

#Auto Scaling:
# Autoscaler: Create an autoscaler for VM instances
resource "google_compute_autoscaler" "ncorium-autoscaler" {
  name  = "ncorium-my-autoscaler"
  zone  = var.zone
  target = google_compute_instance_group_manager.ncorium-default.self_link

  autoscaling_policy {
    max_replicas     = 2
    min_replicas     = 1
    cooldown_period  = 60

    cpu_utilization {
      target = 0.5
    }
  }
}

#Health Check:
resource "google_compute_health_check" "autohealing" {
  name                = "autohealing-health-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 10                         # 50 seconds

  http_health_check {
    request_path = "/"
    port         = "80"
  }
}
