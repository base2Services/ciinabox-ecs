require 'cfndsl/rake_task'
require 'rake'
require 'yaml'
require 'erb'
require 'fileutils'
require 'pathname'
require 'net/http'
require 'securerandom'
require 'base64'
require 'tempfile'

namespace :ciinabox do

  #load config
  templates = Dir["templates/**/*.rb"]
  ciinaboxes_dir = ENV['CIINABOXES_DIR'] || 'ciinaboxes'
  ciinabox_name = ENV['CIINABOX'] || ''

  #Load and merge standard ciinabox-provided parameters
  default_params = YAML.load(File.read("config/default_params.yml")) if File.exist?("config/default_params.yml")

  if File.exist?("#{ciinaboxes_dir}/#{ciinabox_name}/config/params.yml")
    user_params = YAML.load(File.read("#{ciinaboxes_dir}/#{ciinabox_name}/config/params.yml"))
    config = default_params.merge(user_params)
  else
    config = default_params
  end

  Dir["#{ciinaboxes_dir}/#{ciinabox_name}/config/*.yml"].each { |config_file|
      if not config_file.include?('params.yml')
        config = config.merge(YAML.load(File.read(config_file)))
      end
  }

  puts config if ENV['DEBUG']

  stack_name = config["stack_name"] || "ciinabox"

  #if {ciinaboxes_dir}/#{ciinabox_name}/templates
  #render and add to templates

  if File.exist?("#{ciinaboxes_dir}/#{ciinabox_name}/templates")
    templates2 = Dir["#{ciinaboxes_dir}/#{ciinabox_name}/templates/**/*.rb"]

    ## we want to exclude overridden templates
    templatesLocalFileNames = templates2.collect { |templateFile| File.basename(templateFile)}
    templates = templates.select { |templateFile| not templatesLocalFileNames.include? File.basename(templateFile)}
    templates = templates + templates2
  end

  files = []
  templates.each do |template|
    filename = "#{template}"
    output = template.sub! /.*templates\//, ''
    output = output.sub! '.rb', '.json'
    files << { filename: filename, output: "output/#{output}" }
  end

  # Generate cloudformation templates, includes packaging of lambda functions
  desc("Generate CloudFormation templates")
  task :generate => ['ciinabox:package_lambdas'] do

    FileUtils.mkdir_p 'output/services'

    # Write config generated by lambda package to tmp file, and pass to templates
    tmp_file = write_config_tmp_file(config)

    CfnDsl::RakeTask.new do |t|
      extras = [[:yaml,'config/default_params.yml']]
      if File.exist? "#{ciinaboxes_dir}/ciinabox_config.yml"
        extras << [:yaml, "#{ciinaboxes_dir}/ciinabox_config.yml"]
      end
      (Dir["#{ciinaboxes_dir}/#{ciinabox_name}/config/*.yml"].map { |f| [:yaml,f]}).each {|c| extras<<c}
      extras << [:ruby,'ext/helper.rb']
      extras << [:yaml, tmp_file.path]
      t.cfndsl_opts = {
          verbose: true,
          files: files,
          extras: extras
      }
    end

    Rake::Task['generate'].invoke
  end

  desc('Initialise a new ciinabox environment')
  task :init do |t, args|

    autogenerated_bucket_name = "ciinabox-deployment-#{SecureRandom.uuid}"

    ciinabox_name = get_input("Enter the name of your ciinabox:")
    ENV['CIINABOX'] = ciinabox_name

    ciinabox_region = get_input("Enter the AWS region to create your ciinabox [us-east-1]:")
    puts 'Using us-east-1 as AWS region' if ciinabox_region.strip == ''
    ciinabox_region = 'us-east-1' if ciinabox_region.strip == ''

    ciinabox_source_bucket = get_input("Enter the name of the S3 bucket to deploy ciinabox to [#{autogenerated_bucket_name}]:")
    ciinabox_source_bucket = autogenerated_bucket_name if ciinabox_source_bucket.strip == ''

    ciinabox_tools_domain = get_input("Enter top level domain (e.g tools.example.com), must exist in Route53 in the same AWS account:")
    ciinabox_aws_profile = get_input("Enter AWS profile you wish to use for provisioning (empty for default):")

    profile_switch = ciinabox_aws_profile != '' ? "--profile #{ciinabox_aws_profile}" : ''
    ciinabox_aws_account = `aws sts get-caller-identity --region #{ciinabox_region} #{profile_switch} --output text --query Account`.sub('\n','').strip

    puts "Using AWS Account #{ciinabox_aws_account}"

    stack_name = get_input("Enter the name of created Cloud Formation stack [ciinabox]:")
    stack_name = 'ciinabox' if(stack_name.strip == '')

    include_dood_slave = yesno("Include docker-outside-of-docker slave", true)
    include_dind_slave = yesno("Include docker-in-docker slave", true)

    use_iam_role = yesno("Use existing role for CIINABOX cluster", true)
    if use_iam_role then
      ciinabox_iam_role_name = get_input('Enter name of iam role to use with CIINABOX cluster [ciinabox]:')
      ciinabox_iam_role_name = 'ciinabox' if ciinabox_iam_role_name.strip == ''
    end

    ciinabox_docker_repo = get_input('Enter name of private docker repository for images [empty for public images]:')

    if ciinabox_name == ''
      puts 'You must enter a name for your ciinabox'
      exit 1
    end

    my_public_ip = get_my_public_ip_address + "/32"
    create_dirs ciinaboxes_dir, ciinabox_name

    #Settings preference - 1) User-input 2) User-provided params.yml 3) Default template

    ciinabox_params = File.read('config/ciinabox_params.yml.erb')
    input_result =  ERB.new(ciinabox_params).result(binding)
    input_hash = YAML.load(input_result) #Converts user input to hash
    if File.exist?("#{ciinaboxes_dir}/#{ciinabox_name}/config/params.yml")
      config_output = user_params.merge(input_hash)  #Merges input hash into user-provided template
      config_yaml = config_output.to_yaml #Convert output to YAML for writing
      File.open("#{ciinaboxes_dir}/#{ciinabox_name}/config/params.yml", 'w') { |f| f.write(config_yaml) }
    else
      File.open("#{ciinaboxes_dir}/#{ciinabox_name}/config/params.yml", 'w') { |f| f.write(input_result) }
    end

    default_services = YAML.load(File.read("config/default_services.yml"))

    class ::Hash
      def deep_merge(second)
        merger = proc { |key, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : Array === v1 && Array === v2 ? v1 | v2 : [:undefined, nil, :nil].include?(v2) ? v1 : v2 }
        self.merge(second.to_h, &merger)
      end
    end

    if File.exist?("#{ciinaboxes_dir}/#{ciinabox_name}/config/services.yml")
      puts "Using user-provided services.yml File"
      user_services = YAML.load(File.read("#{ciinaboxes_dir}/#{ciinabox_name}/config/services.yml"))
      combined_services = default_services.deep_merge(user_services)
      yml_combined_services = combined_services.to_yaml
      File.open("#{ciinaboxes_dir}/#{ciinabox_name}/config/services.yml", 'w') { |f| f.write(yml_combined_services) }
    else
      yml_default_services = default_services.to_yaml
      File.open("#{ciinaboxes_dir}/#{ciinabox_name}/config/services.yml", 'w') { |f| f.write(yml_default_services) }
    end

    display_active_ciinabox ciinaboxes_dir, ciinabox_name
  end

  desc('Switch active ciinabox')
  task :active, :ciinabox do |t, args|
    ciinabox = args[:ciinabox] || ciinabox_name
    display_active_ciinabox ciinaboxes_dir, ciinabox
  end

  desc('Current status of the active ciinabox')
  task :status do
    check_active_ciinabox(config)
    status, result = aws_execute( config, ['cloudformation', 'describe-stacks', "--stack-name #{stack_name}", '--query "Stacks[0].StackStatus"', '--out text'] )
    if status > 0
      puts "fail to get status for #{config['ciinabox_name']}...has it been created?"
      exit 1
    end
    output = result.chop!
    if output == 'CREATE_COMPLETE' || output == 'UPDATE_COMPLETE'
      puts "#{config['ciinabox_name']} ciinabox is alive!!!!"
      display_ecs_ip_address config
    else
      puts "#{config['ciinabox_name']} ciinabox is in state: #{output}"
    end
  end

  desc('Creates the source bucket for deploying ciinabox')
  task :create_source_bucket do
    check_active_ciinabox(config)
    status, result = aws_execute( config, ['s3', 'ls', "s3://#{config['source_bucket']}/ciinabox/#{config['ciinabox_version']}/"] )
    if status > 0
      status, result = aws_execute( config, ['s3', 'mb', "s3://#{config['source_bucket']}"] )
      puts result
      if status > 0
        puts "fail to create source bucket see error logs for details"
        exit status
      else
        puts "Successfully created S3 source deployment bucket #{config['source_bucket']}"
      end
    else
      puts "Source deployment bucket #{config['source_bucket']} already exists"
    end
  end

  desc('Create self-signed SSL certs for use with ciinabox')
  task :create_server_cert do
    check_active_ciinabox(config)
    ciinabox_name = config['ciinabox_name']
    dns_domain = config['dns_domain']
    script = "
    openssl req -nodes -new -x509 -newkey rsa:4096 -days 3650 \
      -keyout #{ciinaboxes_dir}/#{ciinabox_name}/ssl/ciinabox.key \
      -out #{ciinaboxes_dir}/#{ciinabox_name}/ssl/ciinabox.crt \
      -subj '/C=AU/ST=Melbourne/L=Melbourne/O=#{ciinabox_name}/OU=ciinabox/CN=*.#{dns_domain}'
    "
    result = `#{script}`
    puts result
  end

  desc('Uploads SSL server certs for ciinabox')
  task :upload_server_cert  do
    check_active_ciinabox(config)
    ciinabox_name = config['ciinabox_name']
    cert_dir = "#{ciinaboxes_dir}/#{ciinabox_name}"
    status, result = aws_execute( config, [
      'iam', 'upload-server-certificate',
      '--server-certificate-name ciinabox',
      "--certificate-body file://#{cert_dir}/ssl/ciinabox.crt",
      "--private-key file://#{cert_dir}/ssl/ciinabox.key",
      "--certificate-chain file://#{cert_dir}/ssl/ciinabox.crt"
    ])
    if status > 0
      puts "fail to create or update IAM server-certificates. See error logs for details"
      puts result
      exit status
    end
    puts "Successfully uploaded server-certificates"
  end

  desc('Generate ciinabox AWS keypair')
  task :generate_keypair do
    check_active_ciinabox(config)
    ciinabox_name = config['ciinabox_name']
    keypair_dir = "#{ciinaboxes_dir}/#{ciinabox_name}/ssl"
    if File.exists?("#{keypair_dir}/ciinabox.pem")
      puts "keypair for ciinabox #{ciinabox_name} already exists...please delete if you wish to re-create it"
      exit 1
    end
    status, result = aws_execute( config, ['ec2', 'create-key-pair',
      "--key-name ciinabox",
      "--query 'KeyMaterial'",
      "--out text"
    ], "#{keypair_dir}/ciinabox.pem")
    puts result
    if status > 0
      puts "fail to create keypair see error logs for details"
      exit status
    else
      result = `chmod 0600 #{keypair_dir}/ciinabox.pem`
      puts "Successfully created ciinabox ssh keypair"
    end
  end

  desc('Deploy Cloudformation templates to S3')
  task :deploy do
    check_active_ciinabox(config)
    status, result = aws_execute( config, ['s3', 'sync', '--delete', 'output/', "s3://#{config['source_bucket']}/ciinabox/#{config['ciinabox_version']}/"] )
    puts result
    if status > 0
      puts "fail to upload rendered templates to S3 bucket #{config['source_bucket']}"
      exit status
    else
      puts "Successfully uploaded rendered templates to S3 bucket #{config['source_bucket']}"
    end
  end

  desc('Creates the ciinabox environment')
  task :create do
    check_active_ciinabox(config)
    status, result = aws_execute( config, ['cloudformation', 'create-stack',
      "--stack-name #{stack_name}",
      "--template-url https://#{config['source_bucket']}.s3.amazonaws.com/ciinabox/#{config['ciinabox_version']}/ciinabox.json",
      '--capabilities CAPABILITY_IAM'
    ])
    puts result
    if status > 0
      puts "Failed to create ciinabox environment"
      exit status
    else
      puts "Starting creation of ciinabox environment"
    end
  end

  desc('Updates the ciinabox environment')
  task :update do
    check_active_ciinabox(config)
    status, result = aws_execute( config, ['cloudformation', 'update-stack',
      "--stack-name #{stack_name}",
      "--template-url https://#{config['source_bucket']}.s3.amazonaws.com/ciinabox/#{config['ciinabox_version']}/ciinabox.json",
      '--capabilities CAPABILITY_IAM'
    ])
    puts result
    if status > 0
      puts "Failed to update ciinabox environment"
      exit status
    else
      puts "Starting updating of ciinabox environment"
    end
  end

  desc('Turn off your ciinabox environment')
  task :down do
    # Use cfn_manage gem for this
    command = 'stop'
    start_stop_env(command, config)
  end

  desc('Turn on your ciinabox environment')
  task :up do
    # Use cfn_manage gem for this
    command = 'start'
    start_stop_env(command, config)
  end

  desc('Deletes/tears down the ciinabox environment')
  task :tear_down do
    check_active_ciinabox(config)
    STDOUT.puts "Are you sure you want to tear down the #{config['ciinabox_name']} ciinabox? (y/n)"
    input = STDIN.gets.strip
    if input == 'y'
      status, result = aws_execute( config, ['cloudformation', 'delete-stack', "--stack-name #{stack_name}"] )
      puts result
      if status > 0
        puts "fail to tear down ciinabox environment"
        exit status
      else
        puts "Starting tear down of ciinabox environment"
      end
    else
      puts "good choice...keep enjoying your ciinabox"
    end
  end

  desc('SSH into your ciinabox environment')
  task :ssh do
    keypair = "#{ciinaboxes_dir}/#{ciinabox_name}/ssl/ciinabox.pem"
    `ssh-add #{ciinaboxes_dir}/#{ciinabox_name}/ssl/ciinabox.pem`
    puts "# execute the following:"
    puts "ssh -A ec2-user@nata.#{config['dns_domain']} -i #{keypair}"
    puts "# and then"
    puts "ssh #{get_ecs_ip_address(config)}"
  end

  desc('Deploys Lambda Functions source')
  task :package_lambdas do
    if (config['lambdas'] != nil && config['lambdas']['functions'] != nil)
      config['lambdas']['functions'].each do |name, lambda_config|
        code = IO.read("#{ciinaboxes_dir}/#{ciinabox_name}/#{lambda_config['code']}")
        code.force_encoding('UTF-8')
        timestamp = Time.now.getutc.to_i
        config_file_folder = "output/lambdas/#{name}/#{timestamp}"
        # create folder
        FileUtils.mkdir_p config_file_folder
        # zip function
        zip_result = system("zip -j #{config_file_folder}/src.zip #{ciinaboxes_dir}/#{ciinabox_name}/#{lambda_config['code']}")
        if not zip_result
          puts "Creation of deployment archive for Lambda function #{name} failed"
          exit -5
        else
          sha256 = Digest::SHA256.file "#{config_file_folder}/src.zip"
          sha256 = sha256.base64digest
          puts "Created zip package #{config_file_folder}/src.zip for lambda #{name} with digest #{sha256}"
          lambda_config['code_sha256'] = sha256
          lambda_config['timestamp'] = timestamp
        end
      end
    end
  end

  desc('Initialize configuration, create required assets in AWS account, create Cloud Formation stack')
  task :full_install do

      Rake::Task['ciinabox:init'].invoke

      # Reload config
      user_params = YAML.load(File.read("#{ciinaboxes_dir}/#{ciinabox_name}/config/params.yml"))
      config = default_params.merge(user_params)

      if(yesno('Create source bucket',true))
        Rake::Task['ciinabox:create_source_bucket'].invoke
      end

      if(yesno('Create and upload server certificate',true))
        Rake::Task['ciinabox:create_server_cert'].invoke
        Rake::Task['ciinabox:upload_server_cert'].invoke
      end

      # Create ciinabox keypair
      if(yesno('Create and upload ciinabox key',true))
        Rake::Task['ciinabox:generate_keypair'].invoke
      end

      # Generate CF
      Rake::Task['ciinabox:generate'].invoke

      # Deploy CF
      Rake::Task['ciinabox:deploy'].invoke

      # Create stack
      Rake::Task['ciinabox:create'].invoke

      puts "Waiting for Cloud Formation stack creation completion ..."
      aws_execute(config,["cloudformation wait stack-create-complete --stack-name #{stack_name}"])

  end



  def check_active_ciinabox(config)
    if(config.nil? || config['ciinabox_name'].nil?)
      puts "no active ciinabox please...run rake ciinabox:active or ciinabox:init"
      exit 1
    end
  end

  def aws_execute(config, cmd, output = nil)
    config['aws_profile'].nil? ? '' : cmd << "--profile #{config['aws_profile']}"
    config['aws_region'].nil? ? '' : cmd << "--region #{config['aws_region']}"
    args = cmd.join(" ")
    if config['log_level'] == :debug
      puts "executing: aws #{args}"
    end
    if output.nil?
      result = `aws #{args} 2>&1`
    else
      result = `aws #{args} > #{output}`
    end
    return $?.to_i, result
  end

  def display_active_ciinabox(ciinaboxes_dir, ciinabox)
    puts "# Enable active ciinabox by executing or override ciinaboxes base directory:"
    puts "export CIINABOXES_DIR=\"#{ciinaboxes_dir}\""
    puts "export CIINABOX=\"#{ciinabox}\""
    puts "# or run"
    puts "# eval \"$(rake ciinabox:active[#{ciinabox}])\""
  end

  def display_ecs_ip_address(config)
    ip_address = get_ecs_ip_address(config)
    if ip_address.nil?
      puts "Unable to get ECS cluster private ip"
    else
      puts "ECS cluster private ip:#{ip_address}"
    end
  end

  def get_ecs_ip_address(config)
    status, result = aws_execute( config, [
      'ec2',
      'describe-instances',
      '--query Reservations[*].Instances[?Tags[?Value==\`ciinabox-ecs\`]].PrivateIpAddress',
      '--out text'
    ])
    if status > 0
      return nil
    else
      return result
    end
  end

  def yesno(question, default)
    question = ("#{question} (y/n)? [#{default ? 'y':'n'}]")
    while true
      case get_input(question)
        when 'Y', 'y', 'yes'
          return true
        when /\A[nN]o?\Z/ #n or no
          return false
      end
    end
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

  def get_my_public_ip_address
    Net::HTTP.get(URI("http://api.ipify.org"))
  end

  def write_config_tmp_file(config)
    #write config to tmp file
    tmp_file = Tempfile.new(%w(config_obj .yml))
    tmp_file << {config: config}.to_yaml
    tmp_file.rewind
    return tmp_file
  end

  def start_stop_env(command, config)
    cmd = "cfn_manage #{command}-environment --stack-name #{config['stack_name']} "
    cmd += " --source-bucket #{config['source_bucket']}"
    cmd += " --region #{config['source_region']}"
    cmd += " --profile #{config['aws_profile']}" if not config['aws_profile'].nil?
    result = system(cmd)
    exit -1 if not result
  end
end
