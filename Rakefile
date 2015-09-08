require 'cfndsl/rake_task'
require 'rake'
require 'yaml'

#load config
config = YAML.load(File.read("config/default_params.yml"))

CfnDsl::RakeTask.new do |t|
  t.cfndsl_opts = {
    verbose: true,
    files: [
      {
        filename: 'templates/ciinabox.rb',
        output: 'output/ciinabox.json'
      },
      {
        filename: 'templates/vpc.rb',
        output: 'output/vpc.json'
      }
    ],
    extras: [
      [ :yaml, 'config/default_params.yml' ],
      [ :ruby, 'ext/helper.rb']
    ]
  }
end

desc('deploy cloudformation templates to S3')
task :deploy do
  cmd = ['s3', 'sync', '--delete', 'output/', "s3://#{config['source_bucket']}/ciinabox/#{config['ciinabox_version']}/"]
  config['aws_profile'].nil? ? '' : cmd << "--profile #{config['aws_profile']}"
  config['aws_region'].nil? ? '' : cmd << "--region #{config['aws_region']}"
  args = cmd.join(" ")
  puts "executing: aws #{args}"
  result = `aws #{args}`
  puts result
  if $?.to_i > 0
    puts "fail to upload rendered templates to S3 bucket #{config['source_bucket']}"
    exit $?.to_i
  else
    puts "Successfully uploaded rendered templates to S3 bucket #{config['source_bucket']}"
  end
end
