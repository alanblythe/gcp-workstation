output "workstation_cluster_name" {
  value = google_workstations_workstation_cluster.default.name
}

output "workstation_config_name" {
  value = google_workstations_workstation_config.default.name
}

output "workstation_name" {
  value = google_workstations_workstation.default.name
}

output "workstation_host" {
  value = google_workstations_workstation.default.host
}

output "workstation_ssh_command" {
  description = "Command to connect to the workstation via SSH"
  value       = "gcloud workstations ssh ${google_workstations_workstation.default.workstation_id} --cluster=${google_workstations_workstation_cluster.default.workstation_cluster_id} --config=${google_workstations_workstation_config.default.workstation_config_id} --region=${var.region} --project=${var.project_id}"
}

output "workstation_start_command" {
  description = "Command to start the workstation"
  value       = "gcloud workstations start ${google_workstations_workstation.default.workstation_id} --cluster=${google_workstations_workstation_cluster.default.workstation_cluster_id} --config=${google_workstations_workstation_config.default.workstation_config_id} --region=${var.region} --project=${var.project_id}"
}

output "workstation_tcp_tunnel_command" {
  description = "Command to open a TCP tunnel to the workstation (Port 22)"
  value       = "gcloud workstations start-tcp-tunnel ${google_workstations_workstation.default.workstation_id} 22 --cluster=${google_workstations_workstation_cluster.default.workstation_cluster_id} --config=${google_workstations_workstation_config.default.workstation_config_id} --region=${var.region} --project=${var.project_id} --local-host-port=localhost:2222"
}

output "vm_internal_ip" {
  description = "The internal IP address of the GCE VM"
  value       = google_compute_instance.vm.network_interface[0].network_ip
}

output "vm_ssh_command" {
  description = "Command to connect to the VM via SSH (IAP)"
  value       = "gcloud compute ssh --zone ${var.zone} ${google_compute_instance.vm.name} --tunnel-through-iap --project ${var.project_id}"
}

output "vm_tcp_tunnel_command" {
  description = "Command to open a TCP tunnel to the VM (Port 22)"
  value       = "gcloud compute start-iap-tunnel ${google_compute_instance.vm.name} 22 --zone=${var.zone} --project=${var.project_id} --local-host-port=localhost:2222"
}