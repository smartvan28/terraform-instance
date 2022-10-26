terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }


  required_version = ">= 0.13"
}


provider "yandex" {
  token     = var.key1
  cloud_id  = var.cloud_id1
  folder_id = var.folder_id1
  zone      = "ru-central1-a"
}

module "smartvan28-network" {
  source  = "smartvan28/smartvan28-network/registry"
  version = "1.0.1"
}

resource "yandex_compute_instance" "test" {
  name        = "test"
  platform_id = "standard-v1"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8qps171vp141hl7g9l"
    }
  }

  network_interface {
    subnet_id = module.smartvan28-network.network_foo_id_subnet
    nat = true
  }

  metadata = {
    foo      = "bar"
    ssh-keys = "ubuntu:${file("./id_rsa.pub")}"
  }
  
  connection {
    type = "ssh"
    user = "ubuntu"
    private_key = "${file("./id_rsa")}"
    host = self.network_interface[0].nat_ip_address
  }
  
  
  provisioner "file" {
  source      = "script.sh"
  destination = "/tmp/script.sh"
  }

  provisioner "remote-exec" {
  inline = [
      "chmod +x /tmp/script.sh",
      "/tmp/script.sh",
    ]
  }


}
 
resource "yandex_lb_target_group" "foo" {
  name      = "my-target-group"
  target {
  subnet_id = module.smartvan28-network.network_foo_id_subnet
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

resource "yandex_dns_zone" "zone1" {
  name        = "my-public-zone"
  description = "Test public zone"

  labels = {
    label1 = "test-public"
  }

  zone    = "docker.smartvan.space."
  public  = true
}

resource "yandex_dns_recordset" "rs1" {
  zone_id = yandex_dns_zone.zone1.id
  name    = "test.docker.smartvan.space."
  type    = "A"
  ttl     = 200
  data    = ["${[for s in yandex_lb_network_load_balancer.foo1.listener: s.external_address_spec.*.address].0[0]}"]
}
