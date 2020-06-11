provider "aws" {

region = "ap-south-1"

profile = "vik_iam1"

}

variable "x" {

type =string
default = "hello this is IAS service using terraform pls enter key to proceed"
}
output "autobot" {
value = "${var.x}"
}

//creating key
variable "enter_key_name" {
 type = string
}

//ceating ec2 instance

resource "aws_instance" "ec2-terraform" {
  ami           = "ami-005956c5f0f757d37"
  instance_type = "t2.micro"
  key_name     = var.enter_key_name
security_groups = ["${aws_security_group.sg.name}"]
  tags = {
    Name = "hmc-os1"
  }
}

//creating security group
//ingress:inbound rule
//outgress:outbound rules

resource "aws_security_group" "sg" {
  name        = "SGservice"
  description = "this is security group for ec2 instance"
  vpc_id      = "vpc-da928fb2"

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
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.esbv1.id
  instance_id = aws_instance.ec2-terraform.id
}


// creating s3 bucket

resource "aws_s3_bucket" "bucket" {
  bucket = "bucket-hmc-task1"
  acl    = "private"

  tags = {
    Name        = "hmc-task1-s3b1"
    Environment = "Dev"
  }
}

//allowing public access or block public access == false

resource "aws_s3_bucket_public_access_block" "allow" {
  bucket = aws_s3_bucket.bucket.id

  block_public_acls   = false
  block_public_policy = false
}

//Uploading a file to a bucket

resource "aws_s3_bucket_object" "object" {

  bucket = aws_s3_bucket.bucket.bucket
  key    = "avengers"
  source = "avengers.jpg" 
// source :give file name and its path

}

// for origin id

locals {
  s3_origin_id = "myS3Origin-Cloudfront"
}

//creating cloud front with s3 as origin

// creating origin access identity

variable "OAI" {
 
type = string

}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "${var.OAI}"
}
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.bucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path}"
    }
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
      restriction_type = "whitelist"
      locations        = ["IN","US", "CA", "GB", "DE"]
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}


// updating bucket policy for accessing buckets objects


data "aws_iam_policy_document" "s3_policy" {
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
  bucket = "${aws_s3_bucket.bucket.id}"
  policy = "${data.aws_iam_policy_document.s3_policy.json}"
}


//creating snapshot of ebs attached for backup


resource "aws_ebs_volume" "example" {
  availability_zone = "us-west-2a"
  size              = 40

  tags = {
    Name = "HelloWorld"
  }
}

resource "aws_ebs_snapshot" "ebs_snapshot" {
  volume_id = "${aws_ebs_volume.esbv1.id}"

  tags = {
    Name = "web-server-snap1"
  }
}