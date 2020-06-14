// aws + terraform  


 //here we goes with the code
provider "aws" {

region = "ap-south-1"

profile = "vik_iam1"

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
    description = "Jenkins server from VPC"
    from_port   = 8080
    to_port     = 8080
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

//creating ebs volume

resource "aws_ebs_volume" "esbv1" {
  
depends_on = [
    aws_instance.ec2-terraform,
  ]

  availability_zone = aws_instance.ec2-terraform.availability_zone
  size              = 1
  tags = {
   Name = "myebsv1"
  }
}
output "ebs_volume_id" {
    value = aws_ebs_volume.esbv1.id
}


output "aws_instance_id" {
    value = aws_instance.ec2-terraform.id
}


//attaching ebs volume

resource "aws_volume_attachment" "ebs_vol_attached" {
  
depends_on = [
    aws_ebs_volume.esbv1,
  ]

  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.esbv1.id
  instance_id = aws_instance.ec2-terraform.id
  force_detach = true
}


// creating s3 bucket

resource "aws_s3_bucket" "bucket" {

depends_on = [
    aws_volume_attachment.ebs_vol_attached,
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

  etag = "${filemd5("C:/Users/HP/Desktop/terra-docs/hmc-task1/aws-terra.png")}"

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


//creating snapshot of ebs attached for backup

resource "aws_ebs_snapshot" "ebs_snapshot" {

depends_on = [
    null_resource.nullremote1,
  ]
  volume_id = "${aws_ebs_volume.esbv1.id}"

  tags = {
    Name = "web-server-snap1"
  }
}
resource "null_resource" "nullremote1"  {

depends_on = [
     aws_volume_attachment.ebs_vol_attached,
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = "${tls_private_key.mykey.private_key_pem}"
    host     = aws_instance.ec2-terraform.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh /var/www/html",
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
   
  inline = ["sudo service httpd start"]
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

