locals {
  lambda_file = "lambda_function"
  lambda_function_name = "invalidate"
  project = "website"
  bucket_website = "tf-${local.project}-4444"
  pipeline_name = "tf-${local.project}-pipeline"
  origin_name = "tf-${local.project}-origin"
}

# S3 Bucket 

resource "aws_s3_bucket" "website" {
  bucket = local.bucket_website
}

resource "aws_s3_bucket_acl" "website_bucket_acl" {
  bucket = aws_s3_bucket.website.id
  acl    = "private"
}

data "aws_iam_policy_document" "website_s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.website.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["${aws_s3_bucket.website.arn}"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }
}

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id
  policy = data.aws_iam_policy_document.website_s3_policy.json
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
}

# Cloudfront

resource "aws_cloudfront_distribution" "website" {
  origin {
    domain_name = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id   = local.origin_name

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.origin_name

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    compress               = true
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }


  ordered_cache_behavior {
    path_pattern     = "/images/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.origin_name

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 1800
    default_ttl            = 1800
    max_ttl                = 1800
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Lambda

data "archive_file" "python_lambda_package" {  
  type = "zip"  
  source_file = "${local.lambda_file}.py" 
  output_path = "${local.lambda_file}.zip"
}

resource "aws_lambda_function" "invalidate" {
        function_name = local.lambda_function_name
        filename      = "${local.lambda_file}.zip"
        source_code_hash = data.archive_file.python_lambda_package.output_base64sha256
        role          = aws_iam_role.lambda_role.arn
        runtime       = "python3.8"
        handler       = "lambda_function.lambda_handler"
        timeout       = 10
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.invalidate.function_name}"
  retention_in_days = 7
  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "lambda_role"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        Action : "sts:AssumeRole",
        Effect : "Allow",
        Principal : {
          "Service" : "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "lambda-policy"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        Effect : "Allow",
        Action : [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource : "arn:aws:logs:*:*:*"
      },
      {
        Effect : "Allow",
        Action : [
            "codepipeline:PutJobFailureResult",
            "codepipeline:PutJobSuccessResult",
            "cloudfront:CreateInvalidation"
        ],
        Resource : "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role = aws_iam_role.lambda_role.id
  policy_arn = aws_iam_policy.lambda_policy.arn
}



# Codepipeline

resource "aws_codepipeline" "codepipeline" {
  name     = local.pipeline_name
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.website.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
        name = "Source"
        category = "Source"
        owner = "ThirdParty"
        provider = "GitHub"
        version = "1"
        output_artifacts = ["source_output"]

        configuration = {
            Owner = var.github_organization
            OAuthToken = var.github_token
            Repo = var.github_repository
            Branch = var.github_branch
        }
    }
   }

  stage {
    name = "Deploy"

    action {
        name = "Deploy"
        category = "Deploy"
        owner = "AWS"
        provider = "S3"
        input_artifacts = ["source_output"]
        version = "1"

        configuration = {
            BucketName = local.bucket_website
            Extract = "true"
        }
    }
  }

  stage {
    name = "Invalidate"

    action {
        name = "Invalidate"
        category = "Invoke"
        owner = "AWS"
        provider = "Lambda"
        input_artifacts = ["source_output"]
        version = "1"

        configuration = {
            FunctionName = local.lambda_function_name
            UserParameters = "{\"distributionId\": \"${aws_cloudfront_distribution.website.id}\", \"objectPaths\": [\"/*\"]}"
        }
        region = var.aws_region
    }
  }
}

resource "aws_iam_role" "codepipeline_role" {
  name = "test-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "codepipeline_policy"
  role = aws_iam_role.codepipeline_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketVersioning",
        "s3:PutObjectAcl",
        "s3:PutObject"
      ],
      "Resource": [
        "${aws_s3_bucket.website.arn}",
        "${aws_s3_bucket.website.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild"
      ],
      "Resource": "*"
    },
    {
      "Action": "lambda:InvokeFunction",
      "Effect": "Allow",
      "Resource": "${aws_lambda_function.invalidate.arn}"
    }
  ]
}
EOF
}

# Codepipeline webhook
resource "aws_codepipeline_webhook" "codepipeline" {
   name            = "${local.pipeline_name}-codepipeline-webhook"
   authentication  = "GITHUB_HMAC"
   target_action   = "Source"
   target_pipeline = "${aws_codepipeline.codepipeline.name}"

   authentication_configuration {
       secret_token = var.webhook_secret
   }

   filter {
       json_path    = "$.ref"
       match_equals = "refs/heads/{Branch}"
   }
}

# Github webhook

resource "github_repository_webhook" "codepipeline" {
   repository = var.github_repository

   configuration {
       url          = "${aws_codepipeline_webhook.codepipeline.url}"
       content_type = "form"
       insecure_ssl = true
       secret       = var.webhook_secret
   }

   events = ["push"]
}