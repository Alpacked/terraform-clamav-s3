## Description

This terraform code uses ClamAV from this [bucket-antivirus-function](https://github.com/upsidetravel/bucket-antivirus-function) repository, but with some changes (*to work in lambda lines*)

Terraform code was taken from this [terraform-s3-clamav](https://github.com/ferozsalam/terraform-s3-clamav) repository. I have updated terraform up-to-best practice and fixed all problems because ClamAV didn't work. 

Our terraforming code works great. **February 24, 2021**

It was tested on terraform *0.13.6* and *0.14.6*

## How it works

- Each time a new object is added to a bucket, S3 invokes the Lambda function to scan the object
- The function package will download current antivirus definitions from a S3 bucket.
- The object is scanned for viruses and malware. Archive files are extracted and the files inside scanned also
- The objects tags are updated to reflect the result of the scan, CLEAN or INFECTED, along with the date and time of the scan.
- If the file is `INFECTED` bucket policy restricts access to the file and you can't open or download it.

## How looks result after scanning
The result can be like this

![Clean](https://i.imgur.com/SSnEsbN.png)
- in the CloudWatch logs

![CLoudWatch Clean](https://i.imgur.com/GHTPqkM.png)
----
Or this

![Infected](https://i.imgur.com/AimtCDS.png)
- in the CloudWatch logs

![CLoudWatch Clean](https://i.imgur.com/c42CCEW.png)

## How to spin up infrastructure

1. `git clone git@github.com:Alpacked/terraform-clamav-s3.git`
2. `cd terraform-clamav-s3`
3. Create `main.tfvars` file with correct `aws_region` and `buckets_to_scan` with list of buckets that ClamAV will be check
4. Run `terraform init`
5. Run `terraform plan -var-file=main.tfvars`
6. Run `terraform apply -var-file=main.tfvars`

**NOTE:** You can find an example of the `tfvars` file in the folder `examples`


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| aws\_region | A region the infrastructure will be deployed in. | `string` | n/a | yes |
| bucket\_events | Specifies event for which to send notifications. | `list(string)` | <pre>[<br>  "s3:ObjectCreated:*"<br>]</pre> | no |
| buckets\_to\_scan | The buckets which need scanning. | `list(string)` | n/a | yes |
| event\_description | The description of the rule. | `string` | `"Fires every three hours"` | no |
| event\_name | The name of the rule. | `string` | `"every_three_hours"` | no |
| event\_schedule\_expression | The scheduling expression. | `string` | `"rate(3 hours)"` | no |
| lambda\_action | The AWS Lambda action you want to allow in this statement. | `string` | `"lambda:InvokeFunction"` | no |
| lambda\_runtime | Identifier of the function's runtime. | `string` | `"python3.7"` | no |
| lambda\_scan\_principal | The principal who is getting this permission. e.g. s3.amazonaws.com, an AWS account ID, <br>or any valid AWS service principal such as events.amazonaws.com or sns.amazonaws.com. | `string` | `"s3.amazonaws.com"` | no |
| lambda\_timeout | Amount of time your Lambda Function has to run in seconds. | `number` | `300` | no |
| lambda\_update\_principal | The principal who is getting this permission. e.g. s3.amazonaws.com, an AWS account ID, <br>or any valid AWS service principal such as events.amazonaws.com or sns.amazonaws.com. | `string` | `"events.amazonaws.com"` | no |
| scan\_handler | Function entrypoint in your code. | `string` | `"scan.lambda_handler"` | no |
| scan\_memory\_size | Amount of memory in MB your Lambda Function can use at runtime. | `number` | `2048` | no |
| update\_handler | Function entrypoint in your code. | `string` | `"update.lambda_handler"` | no |
| update\_memory\_size | Amount of memory in MB your Lambda Function can use at runtime. | `number` | `1024` | no |
