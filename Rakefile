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

desc('creates the ciinabox environment')
task :create do
  cmd = ['aws','cloudformation', 'create-stack', '--stack-name ciinabox', "--template-url https://s3-#{config['aws_region']}.amazonaws.com/#{config['source_bucket']}/ciinabox/#{config['ciinabox_version']}/ciinabox.json", '--capabilities CAPABILITY_IAM']
  config['aws_profile'].nil? ? '' : cmd << "--profile #{config['aws_profile']}"
  config['aws_region'].nil? ? '' : cmd << "--region #{config['aws_region']}"
  args = cmd.join(" ")
  puts "executing: #{args}"
  result = `#{args}`
  puts result
  if $?.to_i > 0
    puts "fail to create ciinabox environment"
    exit $?.to_i
  else
    puts "Starting creation of ciinabox environment"
  end
end

desc('updates the ciinabox environment')
task :update do
  cmd = ['aws','cloudformation', 'update-stack', '--stack-name ciinabox', "--template-url https://s3-#{config['aws_region']}.amazonaws.com/#{config['source_bucket']}/ciinabox/#{config['ciinabox_version']}/ciinabox.json", '--capabilities CAPABILITY_IAM']
  config['aws_profile'].nil? ? '' : cmd << "--profile #{config['aws_profile']}"
  config['aws_region'].nil? ? '' : cmd << "--region #{config['aws_region']}"
  args = cmd.join(" ")
  puts "executing: #{args}"
  result = `#{args}`
  puts result
  if $?.to_i > 0
    puts "fail to update ciinabox environment"
    exit $?.to_i
  else
    puts "Starting updating of ciinabox environment"
  end
end

desc('delete/tears down the ciinabox environment')
task :tear_down do
  STDOUT.puts "Are you sure? (y/n)"
  input = STDIN.gets.strip
  if input == 'y'
    cmd = ['aws','cloudformation', 'delete-stack', '--stack-name ciinabox']
    config['aws_profile'].nil? ? '' : cmd << "--profile #{config['aws_profile']}"
    config['aws_region'].nil? ? '' : cmd << "--region #{config['aws_region']}"
    args = cmd.join(" ")
    puts "executing: #{args}"
    result = `#{args}`
    puts result
    if $?.to_i > 0
      puts "fail to tear down ciinabox environment"
      exit $?.to_i
    else
      puts "Starting tear down of ciinabox environment"
    end
  else
    puts "good choice...keep enjoying your ciinabox"
  end

end
