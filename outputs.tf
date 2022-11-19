output "network_address" {
  value = yandex_compute_instance.test.network_interface.0.nat_ip_address
}
