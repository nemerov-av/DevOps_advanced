variable "yc_cloud_id" {
  type = string
}

variable "yc_folder_id" {
  type = string
}

variable "service_account_id" {
  type = string
}

variable "ssh_key_path" {
  type = string
}

# ==============================================================================
# 1. Сеть и подсети
# ==============================================================================
resource "yandex_vpc_network" "vpc_hw" {
  name = "hw-network"
}

resource "yandex_vpc_subnet" "subnet_dmz" {
  name           = "dmz"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.vpc_hw.id
  v4_cidr_blocks = ["10.0.1.0/24"]
}

resource "yandex_vpc_subnet" "subnet_app1" {
  name           = "app1"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.vpc_hw.id
  v4_cidr_blocks = ["10.0.2.0/24"]
}

resource "yandex_vpc_subnet" "subnet_app2" {
  name           = "app2"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.vpc_hw.id
  v4_cidr_blocks = ["10.0.3.0/24"]
}

resource "yandex_vpc_subnet" "subnet_db1" {
  name           = "db1"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.vpc_hw.id
  v4_cidr_blocks = ["10.0.4.0/24"]
}

resource "yandex_vpc_subnet" "subnet_db2" {
  name           = "db2"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.vpc_hw.id
  v4_cidr_blocks = ["10.0.5.0/24"]
}

# ==============================================================================
# 2. Security Groups (Настройка доступов по подсетям)
# ==============================================================================
resource "yandex_vpc_security_group" "sg_dmz" {
  name       = "sg-dmz"
  network_id = yandex_vpc_network.vpc_hw.id

  ingress {
    protocol       = "TCP"
    description    = "Allow SSH"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }
  ingress {
    protocol       = "TCP"
    description    = "Allow HTTP from Internet"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }
  egress {
    protocol       = "ANY"
    description    = "Allow any outbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "sg_app1" {
  name       = "sg-app1"
  network_id = yandex_vpc_network.vpc_hw.id

  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }
  ingress {
    protocol       = "TCP"
    description    = "Allow HTTP from DMZ"
    v4_cidr_blocks = ["10.0.1.0/24"]
    port           = 80
  }
  ingress {
    protocol       = "TCP"
    description    = "Allow HTTP from App2"
    v4_cidr_blocks = ["10.0.3.0/24"]
    port           = 80
  }
  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "sg_app2" {
  name       = "sg-app2"
  network_id = yandex_vpc_network.vpc_hw.id

  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }
  ingress {
    protocol       = "TCP"
    description    = "Allow HTTP from DMZ"
    v4_cidr_blocks = ["10.0.1.0/24"]
    port           = 80
  }
  ingress {
    protocol       = "TCP"
    description    = "Allow HTTP from App1"
    v4_cidr_blocks = ["10.0.2.0/24"]
    port           = 80
  }
  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "sg_db1" {
  name       = "sg-db1"
  network_id = yandex_vpc_network.vpc_hw.id

  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }
  ingress {
    protocol       = "TCP"
    description    = "Allow HTTP ONLY from App1"
    v4_cidr_blocks = ["10.0.2.0/24"]
    port           = 80
  }
  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "sg_db2" {
  name       = "sg-db2"
  network_id = yandex_vpc_network.vpc_hw.id

  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }
  ingress {
    protocol       = "TCP"
    description    = "Allow HTTP ONLY from App2"
    v4_cidr_blocks = ["10.0.3.0/24"]
    port           = 80
  }
  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# ==============================================================================
# 3. Виртуальные машины (с именами хостов и корректным cloud-init)
# ==============================================================================
locals {
  image_id = "fd8stihmr1nt96879jfg" # Ubuntu 20.04 LTS
}

resource "yandex_compute_instance" "dmz" {
  name        = "dmz"
  hostname    = "dmz"
  platform_id = "standard-v1"
  zone        = "ru-central1-a"
  
  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }
  
  boot_disk {
    initialize_params {
      image_id = local.image_id
    }
  }
  
  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet_dmz.id
    ip_address         = "10.0.1.10"
    nat                = true
    security_group_ids = [yandex_vpc_security_group.sg_dmz.id]
  }
  
  metadata = {
    ssh-keys  = "ubuntu:${file(var.ssh_key_path)}"
    user-data = <<-EOF
      #cloud-config
      package_update: true
      packages:
        - nginx
      write_files:
        - path: /etc/nginx/conf.d/default.conf
          content: |
            upstream backend {
                random;
                server 10.0.2.10;
                server 10.0.3.10;
            }
            server {
                listen 80;
                location / {
                    proxy_pass http://backend;
                    add_header X-Proxy-By "DMZ-LoadBalancer";
                }
            }
      runcmd:
        - rm -f /etc/nginx/sites-enabled/default
        - systemctl restart nginx
    EOF
  }
}

resource "yandex_compute_instance" "app1" {
  name        = "app1"
  hostname    = "app1"
  platform_id = "standard-v1"
  zone        = "ru-central1-a"
  
  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }
  
  boot_disk {
    initialize_params {
      image_id = local.image_id
    }
  }
  
  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet_app1.id
    ip_address         = "10.0.2.10"
    nat                = true
    security_group_ids = [yandex_vpc_security_group.sg_app1.id]
  }
  
  metadata = {
    ssh-keys  = "ubuntu:${file(var.ssh_key_path)}"
    user-data = <<-EOF
      #cloud-config
      package_update: true
      packages:
        - nginx
      write_files:
        - path: /etc/nginx/conf.d/default.conf
          content: |
            server {
                listen 80;
                location / {
                    proxy_pass http://10.0.4.10;
                    sub_filter 'DB1' 'App1 -> DB1';
                    sub_filter_once off;
                }
            }
      runcmd:
        - rm -f /etc/nginx/sites-enabled/default
        - systemctl restart nginx
    EOF
  }
}

resource "yandex_compute_instance" "app2" {
  name        = "app2"
  hostname    = "app2"
  platform_id = "standard-v1"
  zone        = "ru-central1-b"
  
  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }
  
  boot_disk {
    initialize_params {
      image_id = local.image_id
    }
  }
  
  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet_app2.id
    ip_address         = "10.0.3.10"
    nat                = true
    security_group_ids = [yandex_vpc_security_group.sg_app2.id]
  }
  
  metadata = {
    ssh-keys  = "ubuntu:${file(var.ssh_key_path)}"
    user-data = <<-EOF
      #cloud-config
      package_update: true
      packages:
        - nginx
      write_files:
        - path: /etc/nginx/conf.d/default.conf
          content: |
            server {
                listen 80;
                location / {
                    proxy_pass http://10.0.5.10;
                    sub_filter 'DB2' 'App2 -> DB2';
                    sub_filter_once off;
                }
            }
      runcmd:
        - rm -f /etc/nginx/sites-enabled/default
        - systemctl restart nginx
    EOF
  }
}

resource "yandex_compute_instance" "db1" {
  name        = "db1"
  hostname    = "db1"
  platform_id = "standard-v1"
  zone        = "ru-central1-a"
  
  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }
  
  boot_disk {
    initialize_params {
      image_id = local.image_id
    }
  }
  
  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet_db1.id
    ip_address         = "10.0.4.10"
    nat                = true
    security_group_ids = [yandex_vpc_security_group.sg_db1.id]
  }
  
  metadata = {
    ssh-keys  = "ubuntu:${file(var.ssh_key_path)}"
    user-data = <<-EOF
      #cloud-config
      package_update: true
      packages:
        - nginx
      write_files:
        - path: /var/www/html/index.html
          content: |
            [Database tier: DB1]
        - path: /etc/nginx/conf.d/default.conf
          content: |
            server {
                listen 80;
                location / {
                    root /var/www/html;
                    index index.html;
                }
            }
      runcmd:
        - rm -f /etc/nginx/sites-enabled/default
        - systemctl restart nginx
    EOF
  }
}

resource "yandex_compute_instance" "db2" {
  name        = "db2"
  hostname    = "db2"
  platform_id = "standard-v1"
  zone        = "ru-central1-b"
  
  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }
  
  boot_disk {
    initialize_params {
      image_id = local.image_id
    }
  }
  
  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet_db2.id
    ip_address         = "10.0.5.10"
    nat                = true
    security_group_ids = [yandex_vpc_security_group.sg_db2.id]
  }
  
  metadata = {
    ssh-keys  = "ubuntu:${file(var.ssh_key_path)}"
    user-data = <<-EOF
      #cloud-config
      package_update: true
      packages:
        - nginx
      write_files:
        - path: /var/www/html/index.html
          content: |
            [Database tier: DB2]
        - path: /etc/nginx/conf.d/default.conf
          content: |
            server {
                listen 80;
                location / {
                    root /var/www/html;
                    index index.html;
                }
            }
      runcmd:
        - rm -f /etc/nginx/sites-enabled/default
        - systemctl restart nginx
    EOF
  }
}

# ==============================================================================
# 4. Выводы (Outputs) для сдачи задания
# ==============================================================================
output "ip_addresses" {
  value = {
    "DMZ"  = yandex_compute_instance.dmz.network_interface.0.nat_ip_address
    "App1" = yandex_compute_instance.app1.network_interface.0.nat_ip_address
    "App2" = yandex_compute_instance.app2.network_interface.0.nat_ip_address
    "DB1"  = yandex_compute_instance.db1.network_interface.0.nat_ip_address
    "DB2"  = yandex_compute_instance.db2.network_interface.0.nat_ip_address
  }
}