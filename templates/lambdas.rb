require 'cfndsl'
require 'digest'
require 'base64'
require_relative '../ext/policies'
class Lambdas


  def initialize(config)
    puts config
    @config = config
  end

  def create_stack()
    ciinaboxes_dir = ENV['CIINABOXES_DIR'] || 'ciinaboxes'
    source_bucket = @config['source_bucket']
    config = @config
    CloudFormation do

      # Template metadata
      AWSTemplateFormatVersion "2010-09-09"
      Description "ciinabox - Lambda Functions v#{config['ciinabox_version']}"

      # Parameters
      Parameter("EnvironmentType") { Type 'String' }
      Parameter("EnvironmentName") { Type 'String' }
      Parameter("VPC") { Type 'String' }

      # Route Tables
      Parameter("RouteTablePrivateA") { Type 'String' }
      Parameter("RouteTablePrivateB") { Type 'String' }

      # Public Subnets
      Parameter("SubnetPublicA") { Type 'String' }
      Parameter("SubnetPublicB") { Type 'String' }

      # Security Groups
      Parameter("SecurityGroupBackplane") { Type 'String' }
      Parameter("SecurityGroupOps") { Type 'String' }
      Parameter("SecurityGroupDev") { Type 'String' }

      Mapping('EnvironmentType', config['Mappings']['EnvironmentType'])

      ## Subnets for Lambdas
      config['availability_zones'].each do |az|
        Resource("SubnetPrivate#{az}") {
          Type 'AWS::EC2::Subnet'
          Property('VpcId', Ref('VPC'))
          Property('CidrBlock', FnJoin("", [FnFindInMap('EnvironmentType', 'ciinabox', 'NetworkPrefix'), ".", FnFindInMap('EnvironmentType', 'ciinabox', 'StackOctet'), ".", config['lambdaSubnets']["SubnetOctet#{az}"], ".0/", FnFindInMap('EnvironmentType', 'ciinabox', 'SubnetMask')]))
          Property('AvailabilityZone', FnSelect(config['azId'][az], FnGetAZs(Ref("AWS::Region"))))
          Property('Tags', [{ Key: 'Name', Value: "ciinabox-lambda-private-#{az}" }])
        }
      end

      config['availability_zones'].each do |az|
        Resource("SubnetRouteTableAssociationPrivate#{az}") {
          Type 'AWS::EC2::SubnetRouteTableAssociation'
          Property('SubnetId', Ref("SubnetPrivate#{az}"))
          Property('RouteTableId', Ref("RouteTablePrivate#{az}"))
        }
      end

      config['lambdas']['functions'].each do |name, lambda_config|


        environment = lambda_config['environment'] || {}
        environment['LAMBDA_PACKAGE_TIMESTAMP'] = lambda_config['timestamp']
        environment['LAMBDA_PACKAGE_SHA256'] = lambda_config['code_sha256']

        # Create Role for Lambda function
        role_name = lambda_config['role']
        role_config = config['lambdas']['roles'][role_name]
        Resource("LambdaRole#{role_name}") do
          Type 'AWS::IAM::Role'
          Property('AssumeRolePolicyDocument', Statement: [
              Effect: 'Allow',
              Principal: { Service: ['lambda.amazonaws.com'] },
              Action: ['sts:AssumeRole']
          ])
          Property('Path', '/')
          unless role_config['policies_inline'].nil?
            Property('Policies', Policies.new.create_policies(role_config['policies_inline']))
          end

          unless role_config['policies_managed'].nil?
            Property('ManagedPolicyArns', role_config['policies_managed'])
          end
        end

        # Create Lambda function
        function_name = name
        Resource(function_name) do
          Type 'AWS::Lambda::Function'
          Property('Code', S3Bucket: source_bucket,
              S3Key: "ciinabox/#{config['ciinabox_version']}/lambdas/#{name}/#{lambda_config['timestamp']}/src.zip")
          Property('Environment', Variables: Hash[environment.collect { |k, v| [k, v] }])
          Property('Handler', lambda_config['handler'] || 'index.handler')
          Property('MemorySize', lambda_config['memory'] || 128)
          Property('Role', FnGetAtt("LambdaRole#{lambda_config['role']}", 'Arn'))
          Property('Runtime', lambda_config['runtime'])
          Property('Timeout', lambda_config['timeout'] || 10)
          if (lambda_config['vpc'] != nil && lambda_config['vpc'])
            Property('VpcConfig', {
                SubnetIds: config['availability_zones'].collect { |az| Ref("SubnetPrivate#{az}") },
                SecurityGroupIds: [Ref('SecurityGroupBackplane')]
            })
          end
          if !lambda_config['named'].nil? && lambda_config['named']
            Property('FunctionName', name)
          end
        end

        Output("Lambda#{function_name}Arn") {
          Value(
              FnGetAtt(function_name, 'Arn')
          )
        }

        # Create Lambda version
        sha256 = lambda_config['code_sha256']
        Resource("#{name}Version#{lambda_config['timestamp']}") do
          Type 'AWS::Lambda::Version'
          DeletionPolicy 'Retain'
          Property('FunctionName', Ref(name))
          Property('CodeSha256', sha256)
        end

        lambda_config['allowed_sources'] = [] if lambda_config['allowed_sources'].nil?

        # if lambda has schedule defined
        if lambda_config.key?('schedules')
          lambda_config['allowed_sources'] << { 'principal' => 'events.amazonaws.com' }
          lambda_config['schedules'].each_with_index do |schedule, index|
            Resource("Lambda#{name}Schedule#{index}") do
              Type 'AWS::Events::Rule'
              Condition(schedule['condition']) if schedule.key?('condition')
              Property('ScheduleExpression', "cron(#{schedule['cronExpression']})")
              Property('State', 'ENABLED')
              target = {
                  'Arn' => FnGetAtt(name, 'Arn'), 'Id' => "lambda#{name}"
              }
              target['Input'] = schedule['payload'] if schedule.key?('payload')
              Property('Targets', [target])
            end
          end
        end

        # Generate lambda function Policy
        unless lambda_config['allowed_sources'].nil?
          i = 1
          lambda_config['allowed_sources'].each do |source|
            Resource("#{name}Permissions#{i}") do
              Type 'AWS::Lambda::Permission'
              Property('FunctionName', Ref(name))
              Property('Action', 'lambda:InvokeFunction')
              Property('Principal', source['principal'])
            end
            i += 1
          end
        end

      end if (config.key? 'lambdas' and (not config['lambdas'].nil?))

    end
  end

end

if defined? lambdas or config.key? 'lambdas'
  lambdas = Lambdas.new(config)
  lambdas.create_stack()
end

