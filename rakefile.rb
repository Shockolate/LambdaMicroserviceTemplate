require 'aws-sdk'
Aws.use_bundled_cert!
require 'rake'
require 'rake/clean'
require 'fileutils'
require 'json'
require 'lambda_wrap'
require 'yaml'
require 'zip'

STDOUT.sync = true
STDERR.sync = true

PWD = File.dirname(__FILE__)
SRC_DIR = File.join(PWD, 'src')
PACKAGE_DIR = File.join(PWD, 'package')
CONFIG_DIR = File.join(PWD, 'config')

CLEAN.include(PACKAGE_DIR)
CLEAN.include(File.join(PWD, 'reports'))
CLOBBER.include(File.join(PWD, 'node_modules'))

# Developer tasks
desc 'Lints, unit tests, and builds the package directory.'
task :build => [:parse_config, :retrieve, :lint, :unit_test, :package]

desc 'Deploys a deployment package to Lambda in the specified environment/stage.'
task :deploy_to_lambda, [:environment] => [:parse_config] do |t, args|
  #validate params
  env = args[:environment]
  raise 'Parameter environment needs to be set' if env.nil?

  # publish to S3
  puts 'Uploading deployment package to S3...'
  t1 = Time.now
  s3_version_id = publish_lambda_package_to_s3()
  t2 = Time.now
  puts "Uploaded deployment package to S3. #{t2 - t1}"

  #deploy functions
  puts 'Deploying Lambda Functions...'
  t1 = Time.now
  CONFIGURATION["functions"].each do |f|
    func_version = deploy_lambda(s3_version_id, f["name"], f["handler"], f["description"])
    promote_lambda(f["name"], func_version, env)
  end
  t2 = Time.now
  puts "Deployed Lambda Functions. #{t2 - t1}"
end

desc 'Deploys OpenAPI (Swagger) Specification to the specified environment/stage with specified
  verbosity. Defaults to DEBUG verbosity if none specified. Uploads swagger file for swagger
  resource if environment == production.'
task :deploy_to_apigateway, [:environment, :verbosity] => [:parse_config] do |t, args|
  env = args[:environment]
  raise 'Parameter environment needs to be set' if env.nil?
  verbos = args[:verbosity]
  verbos = 'DEBUG' if verbos.nil?
  stage_variables = { 'verbosity' => verbos }
  setup_apigateway(env, CONFIGURATION["api_name"], stage_variables)
end

task :deploy_environment, [:environment, :verbosity] => [:build, :deploy_to_lambda, :deploy_to_apigateway]

# Jenkins Targets
# TODO: Implement dependencies.
task :merge_job, [:environment, :verbosity] => [:clean, :parse_config, :retrieve, :lint, :unit_test_report, :coverage, :package, :deploy_environment]
task :pull_request_job => [:clean, :parse_config, :retrieve, :lint, :unit_test_report, :coverage, :package, :integration_test, :e2e_test ]

# Workflow tasks
desc 'Retrieves external dependencies. Calls "npm install"'
task :retrieve do
  cmd = "npm install"
  raise 'Node Modules not installed.' if !system(cmd)
end

desc 'Parses and Lints src and test directories. Calls "npm run lint"'
task :lint do
  cmd = 'npm run lint'
  raise 'Error linting.' if !system(cmd)
end

desc 'Runs code coverage on unit tests'
task :coverage do
  cmd = "npm run cover"
  raise 'Error running code coverage.' if !system(cmd)
end

desc 'Runs Unit tests located in the test/unit directory.
  Calls "npm run unit_test"'
task :unit_test do
  cmd = "npm run unit_test"
  raise 'Error running unit tests.' if !system(cmd)
end

desc 'Runs Unit tests and located in the test/unit directory.
  Outputs results to test-reports.xml. Calls "npm run unit_test_report"'
task :unit_test_report do
  cmd = "npm run unit_test_report"
  raise 'Error running unit tests.' if !system(cmd)
end

desc 'Runs Integration tests located in the test/integration directory.
  Calls "npm run integration_test"'
task :integration_test do
  cmd = "npm run integration_test"
  raise 'Error running integration tests.' if !system(cmd)
end

desc 'Runs End-to-end tests located in the test/e2e directory.
  Calls "npm run e2e_test"'
task :e2e_test do
  cmd = "npm run e2e_test"
  raise 'Error running End-To-End tests.' if !system(cmd)
end

desc 'Creates a package for deployment.'
task :package => [:clean, :parse_config, :retrieve] do
  package()
end

desc 'Promotes an existing Lambda Function with Version to a given environment/stage.'
task :promote, [:environment, :function_name, :function_version] do
  # validate input parameters
  env = args[:environment]
  raise 'Parameter environment needs to be set' if env.nil?
  function_name = args[:function_name]
  raise 'Parameter function needs to be set' if function_name.nil?
  function_version = args[:function_version]
  raise 'Parameter version needs to be set' if function_version.nil?

  # promote a specific lambda function version
  promote_lambda(function_name, function_version, env)
end

desc 'tears down an environment - Removes Lambda Aliases and Deletes API Gateway Stage.'
task :teardown_environment, [:environment] => [:parse_config] do |t, args|
  # validate input parameters
  env = args[:environment]
  raise 'Parameter environment needs to be set' if env.nil?

  teardown_apigateway_stage(env)

  teardown_lambda_aliases(env)
end

desc 'Tears down API Gateway Stage.'
task :teardown_apigateway_stage, [:environment] => [:parse_config] do |t, args|
  env = args[:environment]
  raise 'Parameter environment needs to be set' if env.nil?
  teardown_apigateway_stage(env)
end

desc 'Tears down Lambda Environment.'
task :teardown_lambda_aliases, [:environment] => [:parse_config] do |t, args|
  env = args[:environment]
  raise 'Parameter environment needs to be set' if env.nil?
  teardown_lambda_aliases(env)
end

NODE_MODULES = Array.new
task :parse_config do
  puts 'Parsing config...'
  CONFIGURATION = YAML::load_file(File.join(DOC_DIR, 'config.yaml'))
  JSON.parse(File.read(File.join(PWD, 'package.json')))['dependencies'].each do |key, value|
    NODE_MODULES << key
  end
  swaggerFile = YAML::load_file(File.join(DOC_DIR, 'swagger.yaml'))
  CONFIGURATION['api_name'] = swaggerFile['info']['title']
  puts 'parsed. '
end

def publish_lambda_package_to_s3()
  lm = LambdaWrap::LambdaManager.new()
  return lm.publish_lambda_to_s3(File.join(PACKAGE_DIR, CONFIGURATION["deployment_package_name"]), CONFIGURATION["s3"]["lambda"]["bucket"], CONFIGURATION["s3"]["lambda"]["key"])
end

def deploy_lambda(s3_version_id, function_name, handler_name, lambda_description)

  lambdaMgr = LambdaWrap::LambdaManager.new()
  func_version = lambdaMgr.deploy_lambda(CONFIGURATION["s3"]["lambda"]["bucket"], CONFIGURATION["s3"]["lambda"]["key"], s3_version_id, function_name, handler_name, CONFIGURATION["lambda_role_arn"], lambda_description, CONFIGURATION["subnet_ids"], CONFIGURATION["security_groups"])
  puts "Deployed #{function_name} to function version #{func_version}."
  return func_version

end

def promote_lambda(function_name, func_version, env)
  lambdaMgr = LambdaWrap::LambdaManager.new()
  lambdaMgr.create_alias(function_name, func_version, env)
end

def setup_apigateway(env, api_name, stage_variables)
  # delegate to api gateway manager
  puts "Setting up #{api_name} on API Gateway and deploying to Environment: #{env}...."
  t1 = Time.now
  swagger_file = File.join(DOC_DIR, 'swagger.yaml')
  mgr = LambdaWrap::ApiGatewayManager.new()
  mgr.download_apigateway_importer(CONFIGURATION["s3"]["importer"]["bucket"], CONFIGURATION["s3"]["importer"]["key"])
  uri = mgr.setup_apigateway(api_name, env, swagger_file, 'API: ' + api_name + ' to stage:' + env, stage_variables)
  t2 = Time.now
  puts "API gateway with api name set to #{api_name} and environment #{env} is available at #{uri}"
  puts "Took #{t2 - t1} seconds."

  # Upload API spec for Swagger UI
  if env == 'production'
    upload_swagger_file()
  end
  return uri
end

def upload_swagger_file()
  cleaned_swagger = clean_swagger(YAML::load_file(File.join(DOC_DIR, 'swagger.yaml')))
  puts "uploading Swagger File..."
  s3 = Aws::S3::Client.new()
  s3.put_object(acl: 'public-read', body: cleaned_swagger, bucket: CONFIGURATION["s3"]["swagger"]["bucket"],
    key: CONFIGURATION["s3"]["swagger"]["key"])
  puts "Swagger File uploaded."
end

def package()
  puts 'Zipping source files.....'
  t1 = Time.now
  js_files_in_src = File.join(SRC_DIR, '*.js')
  input_filenames = Dir.glob(js_files_in_src)
  LambdaWrap::LambdaManager.new().package(PACKAGE_DIR, File.join(PACKAGE_DIR, CONFIGURATION["deployment_package_name"]), input_filenames, NODE_MODULES)
  t2 = Time.now
  puts 'Zipped source files. ' + (t2-t1).to_s
  puts 'Downloading secrets zip....'
  t1 = Time.now
  s3 = Aws::S3::Client.new()
  s3.get_object(
    response_target: PACKAGE_DIR + '/' + CONFIGURATION["s3"]["secrets"]["key"],
    bucket: CONFIGURATION["s3"]["secrets"]["bucket"],
    key: CONFIGURATION["s3"]["secrets"]["key"],
  )
  t2 = Time.now
  puts 'Secrets downloaded. ' + (t2-t1).to_s

  secrets_entries = Array.new
  puts 'Extracting Secrets...'

  t1 = Time.now
  Zip::File.open(PACKAGE_DIR + '/' + CONFIGURATION["s3"]["secrets"]["key"]) do |secrets_zip_file|
    secrets_zip_file.each do |entry|
      secrets_entries.push(entry.name)
      entry.extract(PACKAGE_DIR + '/' + entry.name)
    end
  end
  t2 = Time.now
  puts 'Secrets Extracted. ' + (t2 - t1).to_s

  puts 'Adding secrets to package...'
  t1 = Time.now
  Zip::File.open(File.join(PACKAGE_DIR, CONFIGURATION["deployment_package_name"]), Zip::File::CREATE) do |zipfile|
    secrets_entries.each do |entry|
      zipfile.add(entry, PACKAGE_DIR + '/' + entry)
    end
  end
  t2 = Time.now
  puts 'Added secrets to package. ' + (t2 - t1).to_s
  #TODO Cleanup secrets?
  puts "\n"
  puts 'Successfully created the deployment package!'
end

def clean_swagger(swagger_yaml)
  puts "cleaning Swagger File..."
  swagger_yaml["paths"].each do |pathKey, pathValue|
    swagger_yaml["paths"][pathKey].each do |methodKey, methodValue|
      swagger_yaml["paths"][pathKey][methodKey] = methodValue.reject{|key, value| key == "x-amazon-apigateway-integration"}
    end
  end
  swagger_yaml["paths"] = swagger_yaml["paths"].reject{|key, value| key == "/swagger"}
  puts "cleaned."
  return YAML::dump(swagger_yaml).sub(/^(---\n)/, "")
end

def teardown_apigateway_stage(stage)
  puts "Deleting Stage: #{stage} from API: #{CONFIGURATION['api_name']}...."
  t1 = Time.now
  LambdaWrap::ApiGatewayManager.new.shutdown_apigateway(CONFIGURATION["api_name"], stage)
  t2 = Time.now
  puts "Deleted. #{t2 - t1}"
end

def teardown_lambda_aliases(aliasValue)
  puts "Deleting Alias: #{aliasValue} from the lambdas."
  t1 = Time.now
  lm = LambdaWrap::LambdaManager.new()
  CONFIGURATION["functions"].each do |f|
    lm.remove_alias(f["name"], aliasValue)
  end
  t2 = Time.now
  puts "Deleted. #{t2 - t1}"
end
