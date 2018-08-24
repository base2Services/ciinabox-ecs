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
require 'json'
require_relative './ext/common_helper'
require_relative './ext/zip_helper'
require 'aws-sdk-s3'
require 'aws-sdk-cloudformation'
require 'ciinabox-ecs' if Gem::Specification::find_all_by_name('ciinabox-ecs').any?
require 'notifier'

namespace :ciinabox do

  #load config
  current_dir = File.expand_path File.dirname(__FILE__)

  templates = Dir["#{current_dir}/templates/**/*.rb"]
  ciinaboxes_dir = ENV['CIINABOXES_DIR'] || 'ciinaboxes'
  ciinabox_name = ENV['CIINABOX'] || ''

  @ciinaboxes_dir = ciinaboxes_dir
  @ciinabox_name = ciinabox_name

  #Load and merge standard ciinabox-provided parameters
  default_params = YAML.load(File.read("#{current_dir}/config/default_params.yml"))
  default_jenkins_configuration_as_code = YAML.load(File.read("#{current_dir}/config/default_jenkins_configuration_as_code.yml"))
  lambda_params = YAML.load(File.read("#{current_dir}/config/default_lambdas.yml"))
  default_params.merge!(lambda_params)

  if File.exist?("#{ciinaboxes_dir}/#{ciinabox_name}/config/params.yml")
    user_params = YAML.load(File.read("#{ciinaboxes_dir}/#{ciinabox_name}/config/params.yml"))
    config = default_params.merge(user_params)
  else
    user_params = {}
    config = default_params
  end

  if File.exist?("#{ciinaboxes_dir}/#{ciinabox_name}/config/jenkins_configuration_as_code.yml")
    user_jenkins_configuration_as_code = YAML.load(File.read("#{ciinaboxes_dir}/#{ciinabox_name}/config/jenkins_configuration_as_code.yml"))
    jenkins_configuration_as_code = default_jenkins_configuration_as_code.merge(user_jenkins_configuration_as_code)
  else
    user_jenkins_configuration_as_code = {}
    jenkins_configuration_as_code = default_jenkins_configuration_as_code
  end

  Dir["#{ciinaboxes_dir}/#{ciinabox_name}/config/*.yml"].each {|config_file|
    next if config_file.include?('params.yml')
    next if config_file.include?('jenkins_configuration_as_code.yml')
    config = config.merge(YAML.load(File.read(config_file)))
  }

  config['lambdas'] = {} unless config.key? 'lambdas'
  config['lambdas'].extend(config['default_lambdas'])

  # ciinabox binary version
  if Gem.loaded_specs['ciinabox-ecs'].nil?
    config['ciinabox_binary_version'] = `git rev-parse --short HEAD`.gsub("\n", '')
  else
    config['ciinabox_binary_version'] = Gem.loaded_specs['ciinabox-ecs'].version.to_s
  end

  File.write('debug-ciinabox.config.yaml', config.to_yaml) if ENV['DEBUG']

  stack_name = config["stack_name"] || "ciinabox"

  #if {ciinaboxes_dir}/#{ciinabox_name}/templates
  #render and add to templates

  if File.exist?("#{ciinaboxes_dir}/#{ciinabox_name}/templates")
    templates2 = Dir["#{ciinaboxes_dir}/#{ciinabox_name}/templates/**/*.rb"]

    ## we want to exclude overridden templates
    templatesLocalFileNames = templates2.collect {|templateFile| File.basename(templateFile)}
    templates = templates.select {|templateFile| not templatesLocalFileNames.include? File.basename(templateFile)}
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
  task :generate => ['ciinabox:package_lambdas', 'ciinabox:package_cac'] do
    check_active_ciinabox(config)
    FileUtils.mkdir_p 'output/services'

    # Write config generated by lambda package to tmp file, and pass to templates
    tmp_file = write_config_tmp_file(config)

    CfnDsl::RakeTask.new do |t|
      extras = [[:yaml, "#{current_dir}/config/default_params.yml"]]
      extras << [:yaml, "#{current_dir}/config/default_lambdas.yml"]
      if File.exist? "#{ciinaboxes_dir}/ciinabox_config.yml"
        extras << [:yaml, "#{ciinaboxes_dir}/ciinabox_config.yml"]
      end
      (Dir["#{ciinaboxes_dir}/#{ciinabox_name}/config/*.yml"].map {|f| [:yaml, f]}).each {|c| extras << c}
      extras << [:ruby, "#{current_dir}/ext/helper.rb"]
      extras << [:yaml, tmp_file.path]
      t.cfndsl_opts = {
          verbose: true,
          files: files,
          extras: extras
      }
    end

    Rake::Task['generate'].invoke
  end

  # Header output
  def log_header(header)
    puts "\n\n ========== #{header} ========== \n            [#{Time.now}]\n\n\n"
  end

  desc('Initialise a new ciinabox environment')
  task :init do |t, args|

    autogenerated_bucket_name = "ciinabox-deployment-#{SecureRandom.uuid}"

    ciinabox_name = get_input("Enter the name of your ciinabox:")
    @ciinabox_name = ciinabox_name
    ENV['CIINABOX'] = ciinabox_name

    ciinabox_region = get_input("Enter the AWS region to create your ciinabox [us-east-1]:")
    puts 'Using us-east-1 as AWS region' if ciinabox_region.strip == ''
    ciinabox_region = 'us-east-1' if ciinabox_region.strip == ''

    ciinabox_source_bucket = get_input("Enter the name of the S3 bucket to deploy ciinabox to [#{autogenerated_bucket_name}]:")
    ciinabox_source_bucket = autogenerated_bucket_name if ciinabox_source_bucket.strip == ''

    ciinabox_tools_domain = get_input("Enter top level domain (e.g tools.example.com), must exist in Route53 in the same AWS account:")
    ciinabox_aws_profile = get_input("Enter AWS profile you wish to use for provisioning (empty for default):")

    profile_switch = ciinabox_aws_profile != '' ? "--profile #{ciinabox_aws_profile}" : ''
    ciinabox_aws_account = `aws sts get-caller-identity --region #{ciinabox_region} #{profile_switch} --output text --query Account`.sub('\n', '').strip

    puts "Using AWS Account #{ciinabox_aws_account}"

    stack_name = get_input("Enter the name of created Cloud Formation stack [ciinabox]:")
    stack_name = 'ciinabox' if (stack_name.strip == '')

    include_dood_slave = yesno("Include docker-outside-of-docker slave", false)
    include_dind_slave = yesno("Include docker-in-docker slave", true)
    self_signed = yesno("Use selfsigned rather than ACM issued and validated certificate", false)
    acm_auto_issue_validate = !self_signed
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

    ciinabox_params = File.read("#{current_dir}/config/ciinabox_params.yml.erb")
    input_result = ERB.new(ciinabox_params).result(binding)
    input_hash = YAML.load(input_result) #Converts user input to hash
    if File.exist?("#{ciinaboxes_dir}/#{ciinabox_name}/config/params.yml")
      config_output = user_params.merge(input_hash) #Merges input hash into user-provided template
      config_yaml = config_output.to_yaml #Convert output to YAML for writing
      File.open("#{ciinaboxes_dir}/#{ciinabox_name}/config/params.yml", 'w') {|f| f.write(config_yaml)}
    else
      File.open("#{ciinaboxes_dir}/#{ciinabox_name}/config/params.yml", 'w') {|f| f.write(input_result)}
    end

    default_services = YAML.load(File.read("#{current_dir}/config/default_services.yml"))

    class ::Hash
      def deep_merge(second)
        merger = proc {|key, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : Array === v1 && Array === v2 ? v1 | v2 : [:undefined, nil, :nil].include?(v2) ? v1 : v2}
        self.merge(second.to_h, &merger)
      end
    end

    if File.exist?("#{ciinaboxes_dir}/#{ciinabox_name}/config/services.yml")
      puts "Using user-provided services.yml File"
      user_services = YAML.load(File.read("#{ciinaboxes_dir}/#{ciinabox_name}/config/services.yml"))
      combined_services = default_services.deep_merge(user_services)
      yml_combined_services = combined_services.to_yaml
      File.open("#{ciinaboxes_dir}/#{ciinabox_name}/config/services.yml", 'w') {|f| f.write(yml_combined_services)}
    else
      yml_default_services = default_services.to_yaml
      File.open("#{ciinaboxes_dir}/#{ciinabox_name}/config/services.yml", 'w') {|f| f.write(yml_default_services)}
    end

    display_active_ciinabox ciinaboxes_dir, ciinabox_name
  end


  desc('Current status of the active ciinabox')
  task :status do
    check_active_ciinabox(config)
    status, result = aws_execute(config, ['cloudformation', 'describe-stacks', "--stack-name #{stack_name}", '--query "Stacks[0].StackStatus"', '--out text'])
    if status != 0
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
    status, result = aws_execute(config, ['s3', 'ls', "s3://#{config['source_bucket']}/ciinabox/#{config['ciinabox_version']}/"])
    if status != 0
      status, result = aws_execute(config, ['s3', 'mb', "s3://#{config['source_bucket']}"])
      puts result
      if status != 0
        puts "fail to create source bucket see error logs for details"
        exit status
      else
        puts "Successfully created S3 source deployment bucket #{config['source_bucket']}"
      end
    else
      puts "Source deployment bucket #{config['source_bucket']} already exists"
    end
  end

  desc('Watches the status of the active ciinabox')
  task :watch do
    last_status = ""
    while true
      check_active_ciinabox(config)
      status, result = aws_execute(config, ['cloudformation', 'describe-stacks', "--stack-name #{stack_name}", '--query "Stacks[0].StackStatus"', '--out text'])
      if status != 0
        puts "fail to get status for #{config['ciinabox_name']}...has it been created?"
        exit 1
      end
      output = result.chop!
      next if last_status == output
      if output == 'CREATE_COMPLETE' || output == 'UPDATE_COMPLETE'
        puts Time.now.strftime("%Y/%m/%d %H:%M") + " #{config['ciinabox_name']} ciinabox is alive!!!!"
        display_ecs_ip_address config
        exit 0
      elsif output == 'ROLLBACK_COMPLETE'
        puts Time.now.strftime("%Y/%m/%d %H:%M") + " #{config['ciinabox_name']} ciinabox has failed and rolled back"
        exit 1
      else
        puts Time.now.strftime("%Y/%m/%d %H:%M") + " #{config['ciinabox_name']} ciinabox is in state: #{output}"
      end
      last_status = output
      sleep(4)
    end
  end

  desc('Watches the status of the active ciinabox and sends a desktop notification message')
  task :watch_notify do
    last_status = ""
    while true
      check_active_ciinabox(config)
      status, result = aws_execute(config, ['cloudformation', 'describe-stacks', "--stack-name #{stack_name}", '--query "Stacks[0].StackStatus"', '--out text'])
      if status != 0
        if last_status == ""
          puts "fail to get status for #{config['ciinabox_name']}...has it been created?"
          Notifier.notify(
              title: "ciinabox-ecs: #{config['ciinabox_name']}",
              message: "fail to get status for #{config['ciinabox_name']}...has it been created?"
          )
        else
          puts "fail to get status for #{config['ciinabox_name']} disappeared from listing"
          Notifier.notify(
              title: "ciinabox-ecs: #{config['ciinabox_name']}",
              message: "fail to get status for #{config['ciinabox_name']} disappeared from listing"
          )
        end
        exit 1
      end
      output = result.chop!
      next if last_status == output
      if output == 'CREATE_COMPLETE' || output == 'UPDATE_COMPLETE'
        Notifier.notify(
            title: "ciinabox-ecs: #{config['ciinabox_name']}",
            message: "ciinabox is alive!!!!"
        )
        puts Time.now.strftime("%Y/%m/%d %H:%M") + " #{config['ciinabox_name']} ciinabox is alive!!!!"
        display_ecs_ip_address config
        exit 0
      elsif output == 'ROLLBACK_IN_PROGRESS'
        puts Time.now.strftime("%Y/%m/%d %H:%M") + " #{config['ciinabox_name']} ciinabox has failed is being rolledback"
        Notifier.notify(
            title: "ciinabox-ecs: #{config['ciinabox_name']}",
            message: "ciinabox has failed is being rolledback"
            )
      elsif output == 'ROLLBACK_COMPLETE'
        puts Time.now.strftime("%Y/%m/%d %H:%M") + " #{config['ciinabox_name']} rollbck completed"
        Notifier.notify(
            title: "ciinabox-ecs: #{config['ciinabox_name']}",
            message: "rollbck completed"
            )
        exit 1
      else
        puts Time.now.strftime("%Y/%m/%d %H:%M") + " #{config['ciinabox_name']} ciinabox is in state: #{output}"
      end
      last_status = output
      sleep(4)
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
  task :upload_server_cert do
    check_active_ciinabox(config)

    check_active_ciinabox(config)
    ciinabox_name = config['ciinabox_name']
    cert_dir = "#{ciinaboxes_dir}/#{ciinabox_name}"
    status, result = aws_execute(config, [
        'iam', 'upload-server-certificate',
        '--server-certificate-name ciinabox',
        "--certificate-body file://#{cert_dir}/ssl/ciinabox.crt",
        "--private-key file://#{cert_dir}/ssl/ciinabox.key",
        "--certificate-chain file://#{cert_dir}/ssl/ciinabox.crt"
    ])
    if status != 0
      puts "fail to create or update IAM server-certificates. See error logs for details"
      puts result
      exit status
    end

    certificate_arn = JSON.parse(result)['CertificateArn']
    puts "Successfully uploaded ACM certificate #{certificate_arn}."
    # remove_update_ciinabox_config_setting('default_ssl_cert_id', certificate_arn)
    # puts "Ciinabox #{ciinabox_name} config file updated with new cert"
  end

  desc('Generate ciinabox AWS keypair')
  task :generate_keypair do
    check_active_ciinabox(config)
    ciinabox_name = config['ciinabox_name']
    keypair_dir = "#{ciinaboxes_dir}/#{ciinabox_name}/ssl"
    unless config['include_bastion_stack']
      puts "include_bastion_stack is set to false; it's recommend that this is set to true if you wish to ssh to the host."
    end
    if File.exists?("#{keypair_dir}/ciinabox.pem")
      puts "keypair for ciinabox #{ciinabox_name} already exists...please delete if you wish to re-create it"
      exit 1
    end
    status, result = aws_execute(config, ['ec2', 'create-key-pair',
        "--key-name ciinabox",
        "--query 'KeyMaterial'",
        "--out text"
    ], "#{keypair_dir}/ciinabox.pem")
    puts result
    if status != 0
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
    status, result = aws_execute(config, ['s3', 'sync', 'output/', "s3://#{config['source_bucket']}/ciinabox/#{config['ciinabox_version']}/"])
    puts result
    if status != 0
      puts "fail to upload rendered templates to S3 bucket #{config['source_bucket']}"
      exit status
    else
      puts "Successfully uploaded rendered templates to S3 bucket #{config['source_bucket']}"
    end
  end

  desc('Creates the ciinabox environment')
  task :create do
    check_active_ciinabox(config)
    status, result = aws_execute(config, ['cloudformation', 'create-stack',
        "--stack-name #{stack_name}",
        "--template-url https://#{config['source_bucket']}.s3.amazonaws.com/ciinabox/#{config['ciinabox_version']}/ciinabox.json",
        '--capabilities CAPABILITY_IAM'
    ])
    puts result
    if status != 0
      puts "Failed to create ciinabox environment"
      exit status
    else
      puts "Starting creation of ciinabox environment"
    end
  end

  desc('Updates the ciinabox environment')
  task :update do
    check_active_ciinabox(config)
    status, result = aws_execute(config, ['cloudformation', 'update-stack',
        "--stack-name #{stack_name}",
        "--template-url https://#{config['source_bucket']}.s3.amazonaws.com/ciinabox/#{config['ciinabox_version']}/ciinabox.json",
        '--capabilities CAPABILITY_IAM'
    ])
    puts result
    if status != 0
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
      status, result = aws_execute(config, ['cloudformation', 'delete-stack', "--stack-name #{stack_name}"])
      puts result
      if status != 0
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
    unless config['include_bastion_stack']
      puts "include_bastion_stack is set to false; you can't ssh into nothing."
      exit 1
    end
    keypair = "#{ciinaboxes_dir}/#{ciinabox_name}/ssl/ciinabox.pem"
    `ssh-add #{ciinaboxes_dir}/#{ciinabox_name}/ssl/ciinabox.pem`
    puts "# execute the following:"
    puts "ssh -A ec2-user@nata.#{config['dns_domain']} -i #{keypair}"
    puts "# and then"
    puts "ssh #{get_ecs_ip_address(config)}"
  end

  desc('Package Lambda Functions as ZipFiles')
  task :package_lambdas do
    check_active_ciinabox(config)

    # custom lambda modification
    lambda_stack_required = config['acm_auto_issue_validate']
    # in future any new conditions for lambda stack would be added here
    # lambda_stack_required ||= some_new_condition
    config['lambdas'] = nil unless lambda_stack_required

    if !config['lambdas'].nil? && !config['lambdas']['functions'].nil?
      log_header 'Package lambda functions'

      # Clear previous packages

      FileUtils.rmtree 'output/lambdas'

      # Cached downloads map
      cached_downloads = {}
      config['lambdas']['functions'].each do |name, lambda_config|
        timestamp = Time.now.getutc.to_i
        # create folder

        config_file_folder = "output/lambdas/#{name}/#{timestamp}"
        FileUtils.mkdir_p config_file_folder

        # download file if code remote archive
        puts "Processing function #{name}...\n"

        if lambda_config['local']
          lambda_source_path = "#{current_dir}/#{lambda_config['code']}" if lambda_config['local']
          lambda_source_file = File.basename(lambda_source_path)
          tmpdir = "output/package_lambdas/#{name}"
          FileUtils.mkdir_p tmpdir
          FileUtils.cp_r(lambda_source_path, tmpdir)
          lambda_source_path = "#{tmpdir}/#{lambda_source_file}"
        else
          lambda_source_path = "#{ciinaboxes_dir}/#{ciinabox_name}/#{lambda_config['code']}"
        end

        lambda_source_dir = File.dirname(lambda_source_path)

        lambda_source_file = File.basename(lambda_source_path)
        lambda_source_file = '.' if Pathname.new(lambda_source_path).directory?

        lambda_source_dir = lambda_source_path if Pathname.new(lambda_source_path).directory?
        puts "Lambda source path: #{lambda_source_path}"
        puts "Lambda source dir: #{lambda_source_dir}"

        unless lambda_config['package_cmd'].nil?
          package_cmd = "cd #{lambda_source_dir} && #{lambda_config['package_cmd']}"
          puts 'Processing package command...'
          package_result = system(package_cmd)
          unless package_result
            puts "Error packaging lambda function, following command failed\n\n#{package_cmd}\n\n"
            exit -4
          end
        end

        if lambda_config['code'].include? 'http'
          if cached_downloads.key? lambda_config['code']
            puts "Using already downloaded archive #{lambda_config['code']}"
            FileUtils.copy(cached_downloads[lambda_config['code']], "#{config_file_folder}/src.zip")
          else
            puts "Downloading file #{lambda_config['code']} ..."
            File.write("#{config_file_folder}/src.zip", Net::HTTP.get(URI.parse(lambda_config['code'])))
            puts 'Download complete'
            cached_downloads[lambda_config['code']] = "#{config_file_folder}/src.zip"
          end
        else

          zip_generator = Ciinabox::Util::ZipFileGenerator.new(lambda_source_dir,
              "#{config_file_folder}/src.zip")

          zip_generator.write

        end

        sha256 = Digest::SHA256.file "#{config_file_folder}/src.zip"
        sha256 = sha256.base64digest
        puts "Created zip package #{config_file_folder}/src.zip for lambda #{name} with digest #{sha256}"
        lambda_config['code_sha256'] = sha256
        lambda_config['timestamp'] = timestamp
      end

      FileUtils.rmtree 'output/package_lambdas'
    end
  end

  desc('Package Configuration As Code Functions as a TarFile')
  task :package_cac do
    check_active_ciinabox(config)

    unless jenkins_configuration_as_code['jenkins'].nil?
      log_header 'Package contains jenkins configuration'

      FileUtils.rmtree 'output/configurationascode'

      overlay_folder = "output/configurationascode/overlay/"
      FileUtils.mkdir_p overlay_folder

      def windows? #:nodoc:
        RbConfig::CONFIG['host_os'] =~ /^(mswin|mingw|cygwin)/
      end

      dirs = ["#{current_dir}/configurationascode/root/", "#{}/output/configurationascode/overlay/"]
      overlay_tar_file = 'output/configurationascode/overlay.tar'
      puts "Creating tar..."+overlay_tar_file+"\n"
      tar = Minitar::Output.new(overlay_tar_file)
      begin
        dirs.each do |dir|
          Find.find(dir).
              select {|name| File.file?(name) }.
              each do |iname|
            stats = {}
            stat = File.stat(iname)
            stats[:mode]   ||= stat.mode
            stats[:mtime]  ||= stat.mtime
            stats[:size] = stat.size

            if windows?
              stats[:uid]  = nil
              stats[:gid]  = nil
            else
              stats[:uid]  ||= stat.uid
              stats[:gid]  ||= stat.gid
            end

            nname = iname.slice dir.length, iname.length - dir.length
            puts iname, nname

            tar.tar.add_file_simple(nname, stats) do |os|
              stats[:current] = 0
              yield :file_start, nname, stats if block_given?
              File.open(iname, 'rb') do |ff|
                until ff.eof?
                  stats[:currinc] = os.write(ff.read(4096))
                  stats[:current] += stats[:currinc]
                  yield :file_progress, name, stats if block_given?
                end
              end
              yield :file_done, nname, stats if block_given?
            end
          end
        end
      ensure
        tar.close
        FileUtils.rmtree overlay_folder
      end

    end
  end

  desc('Initialize configuration, create required assets in AWS account, create Cloud Formation stack')
  task :full_install do

    Rake::Task['ciinabox:init'].invoke

    # Reload config
    user_params = YAML.load(File.read("#{ciinaboxes_dir}/#{ciinabox_name}/config/params.yml"))
    config = default_params.merge(user_params)

    if (yesno('Create source bucket', true))
      Rake::Task['ciinabox:create_source_bucket'].invoke
    end

    if (yesno("Create and upload server certificate?\n(chose yes if using local hosts file for DNS to tools)", false))
      Rake::Task['ciinabox:create_server_cert'].invoke
      Rake::Task['ciinabox:upload_server_cert'].invoke
      user_params = YAML.load(File.read("#{ciinaboxes_dir}/#{ciinabox_name}/config/params.yml"))
    end

    # Create ciinabox keypair
    if (yesno('Create and upload ciinabox key', true))
      Rake::Task['ciinabox:generate_keypair'].invoke
    end

    # Generate CF
    Rake::Task['ciinabox:generate'].invoke

    # Deploy CF
    Rake::Task['ciinabox:deploy'].invoke

    # Create stack
    Rake::Task['ciinabox:create'].invoke

    puts "Waiting for Cloud Formation stack creation completion ..."
    aws_execute(config, ["cloudformation wait stack-create-complete --stack-name #{stack_name}"])

  end

  desc('Replace previously auto-generated IAM certificate with auto-validated ACM certificate (if one exists)')
  task :update_cert_to_acm do
    status, result = aws_execute(config, [
        'cloudformation',
        'describe-stacks',
        "--stack-name #{stack_name}",
        '--out json'
    ])
    resp = JSON.parse(result)
    cert_output = resp['Stacks'][0]['Outputs'].find {|k| k['OutputKey'] == 'DefaultSSLCertificate'}
    if cert_output.nil?
      STDERR.puts("ACM certificate is not present in stack outputs")
      exit -1
    end
    cert_arn = cert_output['OutputValue']

    # as we don't want to remove any comments
    remove_update_ciinabox_config_setting('default_ssl_cert_id', cert_arn)
    puts "Set #{cert_arn} as default_cert_arn"
  end


  desc('validate cloudformation templates')
  task :validate do
    cfn = Aws::CloudFormation::Client.new(region: config['source_region'])
    s3 = Aws::S3::Client.new(region: config['source_region'])
    Dir.glob("output/**/*.json") do |file|
      template_content = IO.read(file)
      # Skip if empty template generated
      next if (template_content == "null\n")
      template = File.open(file, 'rb')
      filename = File.basename file
      template_bytesize = template_content.bytesize
      file_size = File.size file
      local_validation = (template_content.bytesize < 51200)
      puts "INFO - #{file}: Filesize: #{file_size}, Bytesize: #{template_bytesize}, local validation: #{local_validation}"
      begin
        if not local_validation
          puts "INFO - Copy #{file} -> s3://#{config['source_bucket']}/cloudformation/#{project_name}/validate/#{filename}"
          s3.put_object({
              body: template,
              bucket: "#{config['source_bucket']}",
              key: "cloudformation/#{project_name}/validate/#{filename}",
          })
          template_url = "https://#{config['source_bucket']}.s3.amazonaws.com/cloudformation/#{project_name}/validate/#{filename}"
          puts "INFO - Copied #{file} to s3://#{config['source_bucket']}/cloudformation/#{project_name}/validate/#{filename}"
          puts "INFO - Validating #{template_url}"
        else
          puts "INFO - Validating #{file}"
        end
        begin
          resp = cfn.validate_template({ template_url: template_url }) unless local_validation
          resp = cfn.validate_template({ template_body: template_content }) if local_validation
          puts "INFO - Template #{filename} validated successfully"
        rescue => e
          puts "ERROR - Template #{filename} failed to validate: #{e}"
          exit 1
        end

      rescue => e
        puts "ERROR - #{e.class}, #{e}"
        exit 1
      end
    end
    puts "INFO - #{Dir["output/**/*.json"].count} templates validated successfully"
  end

  desc('vendor templates from ciinabox gem into ciinabox folder')
  task :vendor do
    Dir["#{current_dir}/templates/**/*.rb"].each do |template_path|
      relative_path = template_path.gsub("#{current_dir}/", '')
      target_path = "#{@ciinaboxes_dir}/#{@ciinabox_name}/#{relative_path}"
      target_dir = File.dirname(target_path)
      FileUtils.mkdir_p target_dir
      puts "#{relative_path} -> #{target_path}"
      FileUtils.copy template_path, target_path
    end
  end

  def add_ciinabox_config_setting(element, value)
    file_name = "#{@ciinaboxes_dir}/#{@ciinabox_name}/config/params.yml"
    File.write(file_name,
        "\n" + "#{element}: #{value}",
        File.size(file_name),
        mode: 'a'
    )
  end

  def remove_update_ciinabox_config_setting(element, new_value = '')
    f = File.new("#{@ciinaboxes_dir}/#{@ciinabox_name}/config/params.yml", 'r+')
    found = false
    f.each do |line|
      if line.include?(element)
        # seek back to the beginning of the line.
        f.seek(-line.length, IO::SEEK_CUR)

        # overwrite line with spaces and add a newline char
        f.write('') if new_value.empty?
        f.write("#{element}: #{new_value}") unless new_value.empty?
        f.write("\n")
        found = true
      end
    end
    f.close
    add_ciinabox_config_setting(element, new_value) if ((not found) and (not new_value.empty?))
  end

  def check_active_ciinabox(config)
    if (config.nil? || config['ciinabox_name'].nil?)
      puts "no active ciinabox - either export CIINABOX variable or set ciinabox name as last command line argument"
      exit 1
    end
  end

  def aws_execute(config, cmd, output = nil)
    if `which aws` == "" then
      puts "No awscli found in $PATH (using `which`)"
      exit 1
    end
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
    status, result = aws_execute(config, [
        'ec2',
        'describe-instances',
        '--query Reservations[*].Instances[?Tags[?Value==\`ciinabox-ecs\`]].PrivateIpAddress',
        '--out text'
    ])
    if status != 0
      return nil
    else
      return result
    end
  end

  def yesno(question, default)
    question = ("#{question} (y/n)? [#{default ? 'y' : 'n'}]")
    while true
      case get_input(question)
      when ''
        return default
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
    tmp_file << { config: config }.to_yaml
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
