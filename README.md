# S3 Static Site with CI/CD Pipeline in AWS

## Instructions

1. Install Terraform in your machine.

2. Create a terraform.tfvars file and set variables values

github_organization = ""
github_repository = ""
github_branch = ""
github_token = ""
webhook_secret = ""
aws_region = ""

3. Set aws credentials

```
export AWS_ACCESS_KEY_ID=your_access_key_id
export AWS_SECRET_ACCESS_KEY=your_secret_access_key
```

4. Init terraform configurations
```
terraform init
```

5. Create the infrastructure
```
terraform apply
```

## Considerations

To automate the deployment process, GitHub V1 has been used as the provider of the Stage "Source" in CodePipeline.

github_token has to be created in GitHub -> User Account Settings -> Developer Settings -> Personal Access Tokens -> Generate new token

Here are some guidelines for using GitHub V2, which does not use a token, but requires a manual approval through the console in the CodePipeline service once the infrastructure is deployed.


### Codepipeline Source Stage configuration

```
  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.example.arn
        FullRepositoryId = "${var.github_organization}/${var.github_repository}"
        BranchName       = var.github_branch
      }
    }
  }
```

### Codestarconnections

```
resource "aws_codestarconnections_connection" "example" {
  name          = "example-connection"
  provider_type = "GitHub"
}
```

### Codepipeline policy statement element

```
    {
      "Effect": "Allow",
      "Action": [
        "codestar-connections:UseConnection"
      ],
      "Resource": "${aws_codestarconnections_connection.example.arn}"
    }
```
