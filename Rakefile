require 'cfndsl/rake_task'
require 'rake'
require 'yaml'
require 'erb'
require 'fileutils'

namespace :ciinabox do

  #load config
  templates = Dir["templates/**/*.rb"]
  ciinaboxes_dir = ENV['CIINABOXES_DIR'] || 'ciinaboxes'
  ciinabox_name = ENV['CIINABOX'] || ''
  config = YAML.load(File.read("#{ciinaboxes_dir}/#{ciinabox_name}/config/default_params.yml")) if File.exist?("#{ciinaboxes_dir}/#{ciinabox_name}/config/default_params.yml")

  files = []
  templates.each do |template|
    filename = "#{template}"
    output = template.sub! 'templates/', ''
    output = output.sub! '.rb', '.json'
    files << { filename: filename, output: "output/#{output}" }
  end

  CfnDsl::RakeTask.new do |t|
    t.cfndsl_opts = {
      verbose: true,
      files: files,
      extras: [
        [ :yaml, "#{ciinaboxes_dir}/#{ciinabox_name}/config/default_params.yml" ],
        [ :yaml, 'config/services.yml' ],
        [ :ruby, 'ext/helper.rb']
      ]
    }
  end

  desc('Initialse a new ciinabox environment')
  task :init do |t, args|
    ciinabox_name = get_input("Enter the name of ypur ciinabox:")
    ciinabox_aws_account = get_input("Enter the id of your aws account you wish to use with ciinabox")
    ciinabox_region = get_input("Enter the AWS region to create your ciinabox (e.g: ap-southeast-2):")
    ciinabox_source_bucket = get_input("Enter the name of the S3 bucket to deploy ciinabox to:")
    ciinabox_tools_domain = get_input("Enter top level domain (e.g tools.example.com), must exist in Route53 in the same AWS account:")
    if ciinabox_name == ''
      puts 'You must enter a name for you ciinabox'
      exit 1
    end
    create_dirs ciinaboxes_dir, ciinabox_name
    config_tmpl = File.read("config/default_params.yml.example")
    default_config =  ERB.new(config_tmpl).result(binding)
    File.open("#{ciinaboxes_dir}/#{ciinabox_name}/config/default_params.yml", 'w') { |f| f.write(default_config) }
    display_active_ciinabox ciinaboxes_dir, ciinabox_name
  end

  desc('switch active ciinabox')
  task :active, :ciinabox do |t, args|
    ciinabox = args[:ciinabox] || ciinabox_name
    display_active_ciinabox ciinaboxes_dir, ciinabox
  end

  desc('creates the source bucket for deploying ciinabox')
  task :create_source_bucket do
    cmd = ['s3', 'mb', "s3://#{config['source_bucket']}/ciinabox/#{config['ciinabox_version']}/"]
    config['aws_profile'].nil? ? '' : cmd << "--profile #{config['aws_profile']}"
    config['aws_region'].nil? ? '' : cmd << "--region #{config['aws_region']}"
    args = cmd.join(" ")
    puts "executing: aws #{args}"
    result = `aws #{args}`
    puts result
    if $?.to_i > 0
      puts "fail to create source bucket see error logs for details"
      exit $?.to_i
    else
      puts "Successfully configured aws account you can now deploy and create a ciinabox environment"
    end
  end

  desc('create self-signed SSL certs for use with ciinabox')
  task :create_ssl_certs do
    ciinabox_name = config['ciinabox_name']
    dns_domain = config['dns_domain']
    script = "
    openssl req -nodes -new -x509 \
      -keyout #{ciinaboxes_dir}/#{ciinabox_name}/ssl/ciinabox.key \
      -out #{ciinaboxes_dir}/#{ciinabox_name}/ssl/ciinabox.crt \
      -subj '/C=AU/ST=Melbourne/L=Melbourne/O=#{ciinabox_name}/OU=ciinabox/CN=*.#{dns_domain}'
    "
    result = `#{script}`
    puts result
  end

  desc('upload ssl certs for ciinabox')
  task :upload_ssl_cert  do
    ciinabox_name = config['ciinabox_name']
    cert_dir = "#{ciinaboxes_dir}/#{ciinabox_name}"
    cmd = ['iam', 'upload-server-certificate',
      '--server-certificate-name ciinabox',
      "--certificate-body file://#{cert_dir}/ssl/ciinabox.crt",
      "--private-key file://#{cert_dir}/ssl/ciinabox.key",
      "--certificate-chain file://#{cert_dir}/ssl/ciinabox.crt"
    ]
    config['aws_profile'].nil? ? '' : cmd << "--profile #{config['aws_profile']}"
    config['aws_region'].nil? ? '' : cmd << "--region #{config['aws_region']}"
    args = cmd.join(" ")
    puts "executing: aws #{args}"
    result = `aws #{args}`
    puts result
    if $?.to_i > 0
      puts "fail to create source bucket see error logs for details"
      exit $?.to_i
    else
      puts "Successfully configured aws account you can now deploy and create a ciinabox environment"
    end
  end

  desc('generate ciinabox aws keypair')
  task :generate_keypair do
    ciinabox_name = config['ciinabox_name']
    keypair_dir = "#{ciinaboxes_dir}/#{ciinabox_name}/ssl"
    cmd = ['ec2', 'create-key-pair',
      "--key-name ciinabox",
      "--query 'KeyMaterial'"
    ]
    config['aws_profile'].nil? ? '' : cmd << "--profile #{config['aws_profile']}"
    config['aws_region'].nil? ? '' : cmd << "--region #{config['aws_region']}"
    cmd << "--out text"
    args = cmd.join(" ")
    puts "executing: aws #{args}"
    result = `aws #{args} > #{keypair_dir}/ciinabox.pem`
    puts result
    if $?.to_i > 0
      puts "fail to create keypair see error logs for details"
      exit $?.to_i
    else
      puts "Successfully ciinabox keypair"
    end
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

  def display_active_ciinabox(ciinaboxes_dir, ciinabox)
    puts "# Enable active ciinabox by executing or override ciinaboxes base directory:"
    puts "export CIINABOXES_DIR=\"#{ciinaboxes_dir}\""
    puts "export CIINABOX=\"#{ciinabox}\""
    puts "# or run"
    puts "eval $(rake ciinabox:active[#{ciinabox}])"
  end

  def get_input(prompt)
    puts prompt
    $stdin.gets.chomp
  end

  def create_dirs(dir, name)
    config_dirname = File.dirname("#{dir}/#{name}/config/ignore.txt")
    unless File.directory?(config_dirname)
      FileUtils.mkdir_p(config_dirname)
    end
    ssl_dirname = File.dirname("#{dir}/#{name}/ssl/ignore.txt")
    unless File.directory?(ssl_dirname)
      FileUtils.mkdir_p(ssl_dirname)
    end
    config_dirname
  end
end
