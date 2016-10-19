require 'aws-sdk'
require 'fileutils'
require_relative './helper-aws'
require_relative './helper-common'

def validate_create_environment(config, fail_on_error = false, prompt_on_error = true)
  begin
    validate_key_pair_existance(config)
  rescue Aws::EC2::Errors::InvalidKeyPairNotFound => e
    if (fail_on_error)
      raise 'Error'
    else
      if prompt_on_error
        if (prompt_yes_no("Key pair 'ciinabox' does not exist in region #{config['aws_region']}.\nDo you want to create one?"))

          key_file_name = "#{config['ciinaboxes_dir']}/#{config['ciinabox_name']}/ssl/ciinabox_#{config['aws_region']}.pem"
          ec2client = Aws::EC2::Client.new(region: config['aws_region'])
          response = ec2client.create_key_pair(key_name:'ciinabox')

          File.open(key_file_name, 'w') { |file| file.write(response.data.key_material) }
          `chmod 0600 #{key_file_name}`
          puts "Key pair 'ciinabox' created successfully in region #{config['aws_region']}\nKey has been saved to #{key_file_name}"
        end
      end
    end
  end
end


#Method will execute silently if ciinabox key exists in given config and region
# Otherwise,  Aws::EC2::Errors::InvalidKeyPairNotFound will be raised
def validate_key_pair_existance(config)
  key_name = config['Mappings']['EnvironmentType']['ciinabox']['KeyName']

  #Set AWS SDK credentials from configured profile
  load_awssdk_credentials(config['aws_profile'])

  #Check whatever key exists
  ec2client = Aws::EC2::Client.new(region: config['aws_region'])
  ec2client.describe_key_pairs({'key_names' => [key_name]})
end