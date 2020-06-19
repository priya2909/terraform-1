

provider "aws" {
  region = "ap-south-1"
  profile = "priya"
}

# Creating Key............... 


resource "tls_private_key" "terraform_key" {
  algorithm   = "RSA" 
  rsa_bits = "2048" 
}

#............... Download key................ 
resource "local_file" "privet_key" {
    content     =tls_private_key.terraform_key.private_key_pem
    filename = "terraform.pem"
    file_permission = 0777
}

resource "aws_key_pair" "web_server_key" {
  key_name = "terraform"
  public_key = tls_private_key.terraform_key.public_key_openssh
}

# Creating Security Groop ................

resource "aws_security_group" "terra_security" {
  name        = "webserver"
  description = "Allow webserver inbound traffic"

  ingress {
    description = "SSH Port"         # Allow ssh
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]       
  }

ingress {
    description = "HTTP Port"        #Allow http
    from_port   = 80 
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]        
  }
ingress {
    description = "PING ICMP"        # Allow ICMP for ping 
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]        
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform_webserver"       
  }
}


# ................Createn Ec2 instance ......................


resource "aws_instance" "web" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = "terraform"
  security_groups = [ "webserver" ]
                                       
# ............Connect via SSH and install Requered Software................
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.terraform_key.private_key_pem 
    host     = aws_instance.web.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

  tags = {
    Name = "Webserver"
  }

}

#.............. Create EBS volume and attach with EC2 instance..........

resource "aws_ebs_volume" "ebstest" {
  availability_zone = aws_instance.web.availability_zone
  size              = 1
  tags = {
    Name = "test_ebs"
  }
}


resource "aws_volume_attachment" "ebs_attach" {
  device_name = "/dev/sdh"
  volume_id   = "${aws_ebs_volume.ebstest.id}"
  instance_id = "${aws_instance.web.id}"
  force_detach = true                     #if it is false then terrform cant destroy the volume, Alaways do False(Recomended)
}


output "webserver_ip" {
  value = aws_instance.web.public_ip
}


#............... Formatting Patitions ................

resource "null_resource" "nullremote1"  {

depends_on = [
    aws_volume_attachment.ebs_attach,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.terraform_key.private_key_pem 
    host     = aws_instance.web.public_ip
  }
#............... Clone code from Github.................
provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/priya2909/terraform-1.git /var/www/html/"
    ]
  }
}


# ............. Creating Snapshort ..........


resource "aws_ebs_snapshot" "web_snapshot" {
  volume_id = "${aws_ebs_volume.ebstest.id}"


  tags = {
    Name = "Web_snap"
  }
}


resource "null_resource" "nullremote2" {
        depends_on = [
        null_resource.nullremote1,
        ]
}

resource "null_resource" "nulllocal1" {
  depends_on = [
  null_resource.nullremote1,
  ]
	#................. Automatically open website on the Chrome Browser...................
provisioner "local-exec" {
  command = "chrome  ${aws_instance.web.public_ip}"
   
  }
}

#.................... Create S3 Bucket and upload data from github Repositry...................



resource "aws_s3_bucket" "server-bucket" {
  bucket = "terratest001-bucket"
  acl = "public-read"


  provisioner "local-exec" {
  
      command = "git clone https://github.com/priya2909/terraform-1.git /root/task_1"

  }


 }
#............ uploading Object on S3 Bucket...........
resource "aws_s3_bucket_object" "image_upload" {
  bucket = aws_s3_bucket.server-bucket.bucket
  key 	="priya.png"
  source = "/priya.png"
  acl = "public-read"
  force_destroy = true
  
  }


#.................... create Cloud-front distribution.................

resource "aws_cloudfront_distribution" "distribution" {
  
                    depends_on = [

                         aws_s3_bucket_object.image_upload,               
                      ]
    origin {
      domain_name = "${aws_s3_bucket.server-bucket.bucket_regional_domain_name}"
      origin_id = "S3-${aws_s3_bucket.server-bucket.bucket}"


        custom_origin_config {
            http_port = 80
            https_port = 443
            origin_protocol_policy = "match-viewer"
            origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
        }
}
    
    default_root_object = "priya.png"
    enabled = true


        custom_error_response {
        error_caching_min_ttl = 3000
        error_code = 404
        response_code = 200
        response_page_path = "/priya.png"
    }


    default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods = ["GET", "HEAD"]
        target_origin_id = "S3-${aws_s3_bucket.server-bucket.bucket}"
        forwarded_values {
            query_string = false
	    cookies {
		forward = "none"
	    }
            
        }

        viewer_protocol_policy = "redirect-to-https"
        min_ttl = 0
        default_ttl = 3600
        max_ttl = 86400
    }


    restrictions {
        geo_restriction {
                        restriction_type = "none"
        }
    }

    viewer_certificate {
        cloudfront_default_certificate = true
    }


     connection {
        type    = "ssh"
        user    = "ec2-user"
        host    = aws_instance.web.public_ip
        port    = 22
        private_key = tls_private_key.terraform_key.private_key_pem
     }


     provisioner "remote-exec" {
        inline  = [
            
            "echo '<img src='http://${aws_cloudfront_distribution.distribution.domain_name}/priya.png' width='500' height='500' class='center'>' | sudo tee -a /var/www/html/index.html",
            
           ]
     } 
  }


