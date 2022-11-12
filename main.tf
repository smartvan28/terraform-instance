terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }


  required_version = ">= 0.13"
}  

data "yandex_vpc_subnet" "test_subnet" {
  name = "test_subnet"
}

data "yandex_dns_zone" "zone1" {
  name = "my-public-zone"
}
  
resource "yandex_compute_instance" "test" {
  name        = "test"
  platform_id = "standard-v1"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = "fd8qps171vp141hl7g9l"
    }
  }

  network_interface {
    subnet_id = data.yandex_vpc_subnet.test_subnet.id
    nat = true
  }

  metadata = {
    foo      = "bar"
    ssh-keys = "ubuntu:${file("./id_rsa.pub")}"
  }
  

}

resource "local_file" "inventory" {
  depends_on = [module.smartvan28-instance]
  filename = "./inventory.txt"
  content = <<EOF
  [webserver]
  web1 ansible_host=${yandex_compute_instance.test.network_interface.0.nat_ip_address} ansible_user = ubuntu
  EOF
}
 
resource "yandex_lb_target_group" "foo" {
  name      = "my-target-group"
  target {
  subnet_id = data.yandex_vpc_subnet.test_subnet.id
  address   = yandex_compute_instance.test.network_interface.0.ip_address
}

}  

resource "yandex_lb_network_load_balancer" "foo1" {
  name = "my-network-load-balancer"

  listener {
    name = "my-listener"
    port = 22
    target_port = 22
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  listener {
    name = "service-port"
    port = 8080
    target_port = 8080
     external_address_spec {
      ip_version = "ipv4"
    }
  }
  
    listener {
    name = "exporter-port"
    port = 9100
    target_port = 9100
     external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = "${yandex_lb_target_group.foo.id}"


    healthcheck {
      name = "tcp"
      tcp_options {
        port = 22
      }
    }
  }
}

resource "yandex_dns_recordset" "rs1" {
  zone_id = data.yandex_dns_zone.zone1.id
  name    = "test.docker.smartvan.space."
  type    = "A"
  ttl     = 200
  data    = ["${[for s in yandex_lb_network_load_balancer.foo1.listener: s.external_address_spec.*.address].0[0]}"]
}
