variable "do_token" {}
variable "lavrentyev_key_name" {}
variable "dr_load" {type = list(string)}
variable "dr_virt" {type = list(string)}
variable "aws_my_access_key" {}
variable "aws_my_secret_key" {}

provider "aws" {
        region = "eu-west-1"
        access_key = "${var.aws_my_access_key}"
        secret_key = "${var.aws_my_secret_key}"
}

provider "digitalocean" {
        token = "${var.do_token}"
}

data "aws_route53_zone" "rebrain" {
        name = "devops.rebrain.srwx.net."
}

data "digitalocean_ssh_key" "LAVRENTYEV" {
                name = "${var.lavrentyev_key_name}"
        }

resource "random_password" "load_root_password" {
	count = length(var.dr_load)
	length = 16
  	special = true
  	override_special = "_%@"
	upper = true
	lower = true
	number = true
}

resource "random_password" "virt_root_password" {
        count = length(var.dr_virt)
        length = 16
        special = true
        override_special = "_%@"
        upper = true
        lower = true
        number = true
}

resource "digitalocean_droplet" "balancer" {
        count = length(var.dr_load)
        image  = "ubuntu-18-04-x64"
        name   = element(var.dr_load, count.index)
        region = "nyc1"
        size   = "s-1vcpu-1gb"
        ssh_keys = ["${data.digitalocean_ssh_key.LAVRENTYEV.fingerprint}"]

		provisioner "remote-exec" {
	        	inline = ["echo root:${element(random_password.load_root_password.*.result, count.index)} | chpasswd"]
		connection {
			host = self.ipv4_address
			type = "ssh"
			user = "root"
			private_key = file("/root/.ssh/id_rsa")
			}
		}
        	provisioner "local-exec" {
	                command = "echo ${self.name} ${self.ipv4_address} ${element(random_password.load_root_password.*.result, count.index)} >> devs.txt"
			}

}

resource "aws_route53_record" "aws_load" {
        count = length(var.dr_load)
        zone_id = data.aws_route53_zone.rebrain.zone_id
        name = "${element(var.dr_load, count.index)}.devops.rebrain.srwx.net"
        type = "A"
        ttl = "300"
        records = ["${element(digitalocean_droplet.balancer.*.ipv4_address, count.index)}"]
}

data "template_file" "hostname_load" {
        count = length(var.dr_load)
        template = "${file("templates/hostname.tpl")}"
        vars = {
          name  = "${element(var.dr_load, count.index)}"
        }
}

data "template_file" "ans_inv_load" {
        template = "${file("templates/inv_load.tpl")}"
        vars = {
         balancer_hosts  = "${join("\n",data.template_file.hostname_load.*.rendered)}"
        }
}

resource "null_resource" "load_to_inv" {
        triggers = {
          template = "${data.template_file.ans_inv_load.rendered}"
        }
             provisioner "local-exec" {
               command = "echo \"${data.template_file.ans_inv_load.rendered}\" >> inventory/prod.yml"
             }
}

resource "digitalocean_droplet" "virt" {
        count = length(var.dr_virt)
        image  = "ubuntu-18-04-x64"
        name   = element(var.dr_virt, count.index)
        region = "nyc1"
        size   = "s-1vcpu-1gb"
        ssh_keys = ["${data.digitalocean_ssh_key.LAVRENTYEV.fingerprint}"]

                provisioner "remote-exec" {
                        inline = ["echo root:${element(random_password.virt_root_password.*.result, count.index)} | chpasswd"]
                connection {
                        host = self.ipv4_address
                        type = "ssh"
                        user = "root"
                        private_key = file("/root/.ssh/id_rsa")
                        }
                }
                provisioner "local-exec" {
                        command = "echo ${self.name} ${self.ipv4_address} ${element(random_password.virt_root_password.*.result, count.index)} >> devs.txt"
                        }

}

resource "aws_route53_record" "aws_virt" {
        count = length(var.dr_virt)
        zone_id = data.aws_route53_zone.rebrain.zone_id
        name = "${element(var.dr_virt, count.index)}.devops.rebrain.srwx.net"
        type = "A"
        ttl = "300"
        records = ["${element(digitalocean_droplet.virt.*.ipv4_address, count.index)}"]
}

data "template_file" "hostname_virt" {
        count = length(var.dr_virt)
        template = "${file("templates/hostname.tpl")}"
        vars = {
          name  = "${element(var.dr_virt, count.index)}"
        }
}

data "template_file" "ans_inv_virt" {
        template = "${file("templates/inv_virt.tpl")}"
        vars = {
          site_hosts  = "${join("\n",data.template_file.hostname_virt.*.rendered)}"
        }
}

resource "null_resource" "virt_to_inv" {
        triggers = {
          template = "${data.template_file.ans_inv_virt.rendered}"
        }
             provisioner "local-exec" {
               command = "echo \"${data.template_file.ans_inv_virt.rendered}\" >> inventory/prod.yml"
             }
}

# resource "null_resource" "ansible" {
#        triggers = {
#        count = 1
#	}
#             provisioner "local-exec" {
#               command = "ansible-playbook -i inventory/prod.yml nginx.yml"
#             }
#	depends_on = [
#	     digitalocean_droplet.balancer,
#            aws_route53_record.aws_load,
#	     template_file.hostname_load,
#	     template_file.ans_inv_load,
#	     null_resource.load_to_inv,
#	     digitalocean_droplet.virt,
#             aws_route53_record.aws_virt,
#             template_file.hostname_virt,
#             template_file.ans_inv_virt,
#             null_resource.virt_to_inv
#	]
#}
