// aws + terraform  


 //here we goes with the code
provider "aws" {

region = "ap-south-1"

profile = "iam_user1"

}

resource "tls_private_key" "mykey" {

  algorithm = "RSA"

}

resource "aws_key_pair" "generated_key" {

  key_name   = "mykey"

  public_key = "${tls_private_key.mykey.public_key_openssh}"

  depends_on = [

    tls_private_key.mykey

  ]

}

resource "local_file" "key-file" {

  content  = "${tls_private_key.mykey.private_key_pem}"

  filename = "mykey.pem"

  depends_on = [

    tls_private_key.mykey

  ]

}

//creating vpc

variable "vpc" {
   type = string
}

//creating security group
//ingress:inbound rule
//outgress:outbound rules

resource "aws_security_group" "sg" {
  name        = "SGservice"
  description = "this is security group for ec2 instance"
  vpc_id      = "${var.vpc}"

  ingress {
    description = "http from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
ingress {
    description = "allowing nfs"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

 egress {
    description = "allow all outbound rules"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "launch-wizard-6"
  }
}

//ceating ec2 instance

resource "aws_instance" "ec2-terraform" {

depends_on = [
    aws_security_group.sg,
  ]
  ami           = "ami-005956c5f0f757d37"
  instance_type = "t2.micro"
  key_name     = aws_key_pair.generated_key.key_name
security_groups = ["${aws_security_group.sg.name}"]

connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key ="${tls_private_key.mykey.private_key_pem}"
    host     = aws_instance.ec2-terraform.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo service httpd enable",
      "sudo service  httpd restart ",
    ]
  }

  tags = {
    Name = "hmc-os1"
  }

}

output  "my_ec2_public_ip" {
	value = aws_instance.ec2-terraform.public_ip
}

output  "my_ec2_aval_zone" {
	value = aws_instance.ec2-terraform.availability_zone
}
variable "zone" {
    type = string
    default = "Availability Zone of ec2-instance is "
}

output "avzone" {
  value= "${var.zone}"
}

// creating efs file system

resource "aws_efs_file_system" "my-efs" {
  creation_token = "my-file-system"
  encrypted = "true"
  tags = {
    Name = "MyProduct"
  }
}

output "aws_instance_id" {
    value = aws_instance.ec2-terraform.id
}


//mounting efs_server

resource "aws_efs_mount_target" "mount_target" {
  depends_on = [aws_efs_file_system.my-efs]

  file_system_id = "${aws_efs_file_system.my-efs.id}"
  subnet_id      = "${aws_instance.ec2-terraform.subnet_id}"
  security_groups = [aws_security_group.sg.id]
  

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.mykey.private_key_pem
    host     = aws_instance.ec2-terraform.public_ip
  }
  provisioner "remote-exec" {
        inline  = [
      
      "sudo rm -rf /var/www/html/*",
      
      // mount the efs volume
      
      "sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_file_system.my-efs.dns_name}:/ /var/www/html",
      
      // create fstab entry to ensure automount on reboots
      
      // https://docs.aws.amazon.com/efs/latest/ug/mount-fs-auto-mount-onreboot.html#mount-fs-auto-mount-on-creation
      
      "sudo su -c \"echo '${aws_efs_file_system.my-efs.dns_name}:/ /var/www/html nfs4 defaults,vers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport 0 0' >> /etc/fstab\""
 ]
}
}

// creating s3 bucket

resource "aws_s3_bucket" "bucket" {

depends_on = [
    aws_efs_mount_target.mount_target
  ]

  bucket = "bucket-hmc-task1"
  acl    = "private"

  tags = {
    Name        = "hmc-task1-s3b1"
    Environment = "Dev"
  }
}

//allowing public access or block public access == false

resource "aws_s3_bucket_public_access_block" "allow" {

depends_on = [
    aws_s3_bucket.bucket,
  ]

  bucket = aws_s3_bucket.bucket.id

  block_public_acls   = false
  block_public_policy = false
}

//Uploading a file to a bucket

resource "aws_s3_bucket_object" "object" {
depends_on = [
    aws_s3_bucket_public_access_block.allow,
  ]
  bucket = aws_s3_bucket.bucket.bucket
  key    = "aws-terra.png"
  source = "aws-terra.png" 
  acl =   "public-read"

  etag = "${filemd5("C:/Users/vikas/Desktop/terra-docs/hmc-task2/hmc-task1/aws-terra.png")}"

// source :give file name and its path

}

// for origin id

locals {
  s3_origin_id = "myS3Origin-Cloudfront"
}



// creating origin access identity

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {

  comment = "Some comment"
}

//creating cloud front with s3 as origin

resource "aws_cloudfront_distribution"  "s3_distribution" {
  
depends_on=[

 aws_s3_bucket_object.object,
 null_resource.nullremote1,

]
  origin {
    domain_name = aws_s3_bucket.bucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  // Cache behavior with precedence 0 ie default origin here it is s3


  ordered_cache_behavior {

    path_pattern     = "*.jpg"

    allowed_methods  = ["GET", "HEAD", "OPTIONS"]

    cached_methods   = ["GET", "HEAD", "OPTIONS"]

    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }
   
   price_class = "PriceClass_All"
   
   restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
    connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key ="${tls_private_key.mykey.private_key_pem}"
    host     = aws_instance.ec2-terraform.public_ip
  }

provisioner "remote-exec" {
    inline = [ 
       " sudo su << EOF ",
      " sudo echo \"<img src ='http://${self.domain_name}/${aws_s3_bucket_object.object.key}'  height='400' width='400'>\" >> /var/www/html/mywebpage.html",
       "EOF"
    ]
  }
}

//updating bucket policy

data "aws_iam_policy_document" "s3_policy" {

depends_on=[
aws_cloudfront_distribution.s3_distribution,
]
  statement {
    actions   = ["s3:GetObject"]

    resources = ["${aws_s3_bucket.bucket.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["${aws_s3_bucket.bucket.arn}"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }
}

resource "aws_s3_bucket_policy" "example" {
  depends_on=[
aws_cloudfront_distribution.s3_distribution,
]
  bucket = "${aws_s3_bucket.bucket.id}"
  policy = "${data.aws_iam_policy_document.s3_policy.json}"
}

resource "null_resource" "nullremote1"  {

depends_on = [
     aws_efs_mount_target.mount_target
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = "${tls_private_key.mykey.private_key_pem}"
    host     = aws_instance.ec2-terraform.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/VikashTiwari1208/hmc-task1.git  /var/www/html/"
    ]
  }
}

resource "null_resource" "remote2"{
depends_on= [
aws_cloudfront_distribution.s3_distribution,
]
connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = "${tls_private_key.mykey.private_key_pem}"
    host     = aws_instance.ec2-terraform.public_ip
   }
provisioner "remote-exec" {
   
  inline = ["sudo service httpd enable",
            "sudo service httpd restart"  ]
   }
}
resource "null_resource" "localexec"  {

depends_on = [
  aws_cloudfront_distribution.s3_distribution,
  null_resource.remote2,
]


provisioner "local-exec" {
   
     command="start chrome  ${aws_instance.ec2-terraform.public_ip}/mywebpage.html"
  }

}

