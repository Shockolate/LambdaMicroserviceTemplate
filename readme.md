# Template for future serverless microservices

## Getting started

### Git
1. Install Git
2. Fork this repository
3. Clone the forked repository

### Ruby
1. Download & install [Ruby](https://www.ruby-lang.org/en/). Version shouldn't matter
3. Install the Ruby Gem 'Bundler' via command line: `gem install bundler`
4. Install the rubygem dependencies with Bundler: `bundle install`

### NodeJS
1. This template assumes you're using NodeJS as your runtime environment in lambda
2. Download and Install [NodeJS v4.3.2](https://nodejs.org/download/release/v4.3.2/). AWS Lambda runs on v4.3.2
3. Edit the package.json. Update fields:
  * name
  * version
  * description
  * repository.url
  * author
  * license
4. Install Node Modules and Dependencies: `rake retrieve`

### AWS SDK
1. Install the [AWS CLI](http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-set-up.html)
2. Set environment variables
  * AWS_DEFAULT_REGION  (e.g. eu-west-1)
  * AWS_ACCESS_KEY_ID
  * AWS_SECRET_ACCESS_KEY

### Java
1. Install Java
2. Add Java to PATH
3. Obtain the [API Gateway Importer Tool](https://github.com/awslabs/aws-apigateway-importer) JAR file and upload to an S3 bucket. You can compile from source, or ask Shopfloor for the JAR. Using this tool is temporary until AWS fixes it's unusual swagger validation problems.

### Swagger UI
If you would like to host a swagger UI page (For Example: fis.shop.cimpress.io/v1/swagger ), you will need to host the Swagger UI package, and the swagger file. The FIS achieves this by uploading the static Swagger UI files to S3 for S3 can serve webpages. Then you can add a resource to your swagger file which will act as an HTTP Proxy to the S3 Bucket with the swagger UI files, with a query parameter to the location of the swagger file that you will also upload.

### Set Values in config.yaml
* deployment_package_name - File name of the deployment zip file. Should end in '.zip'.
* lambda_role_arn - The Role ARN that all of the lambdas will assume when executing.
* S3 Lambda Bucket & Key - The S3 Bucket & Key to upload the deployment package to. This bucket must be 'versioned.'
* S3 Secrets Bucket & Key - The S3 Bucket & Key that hosts a zip file that contains any files to deployed within the 'Deployment Package.' An example use could be connection strings that the developer does not want to record with version control.
* S3 Swagger Bucket & Key - The S3 Bucket & Key where you will upload your swagger.yaml to be served by the swagger UI. The rake file will remove implementation details (API Gateway Integration fields) and the swagger resource.
* S3 Importer Bucket & Key - The S3 Bucket & Key where the API Gateway Importer JAR lives. LambdaWrap needs it in order to import your swagger into API Gateway.
* Subnet IDs - a List of Subnet IDs if your service requires to be on a VPN
* Security Groups - a list of Security Group IDs if your service requires to be on a VPN
* Functions - A List of Lambda functions that will be deployed. Each object in the list should have the Name of the Lambda Function, The Handler (ModuleName.MethodName), and an optional Description.
