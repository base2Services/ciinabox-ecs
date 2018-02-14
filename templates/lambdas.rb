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

      config['lambdas']['roles'].each do |lambda_role, role_config|
        Resource("LambdaRole#{lambda_role}") {
          Type 'AWS::IAM::Role'
          Property('AssumeRolePolicyDocument', {
              Statement: [
                  Effect: 'Allow',
                  Principal: { Service: ['lambda.amazonaws.com'] },
                  Action: ['sts:AssumeRole']
              ]
          })
          Property('Path', '/')
          Property('Policies', Policies.new.create_policies(role_config['policies_inline']))

          if (role_config['policies_managed'] != nil)
            Property('ManagedPolicyArns', role_config['policies_managed'])
          end
        }
      end


      config['lambdas']['functions'].each do |name, lambda_config|
        timeout = lambda_config['timeout'] != nil ? lambda_config['timeout'] : 10
        memory = lambda_config['memory'] != nil ? lambda_config['memory'] : 128
        code = IO.read("#{ciinaboxes_dir}/#{config['ciinabox_name']}/#{lambda_config['code']}")
        code.force_encoding('UTF-8')
        environment = lambda_config['environment'] != nil ? lambda_config['environment'] : {}
        Resource(name) do
          Type 'AWS::Lambda::Function'
          Property('Code', {
              S3Bucket: source_bucket,
              S3Key: "ciinabox/#{config['ciinabox_version']}/lambdas/#{name}/#{lambda_config['timestamp']}/src.zip"
          })
          Property('Environment', {
              Variables: Hash[environment.collect { |k, v| [k.upcase, v] }]
          })
          Property('Handler', lambda_config['handler'])
          Property('MemorySize', memory)
          Property('Role', FnGetAtt("LambdaRole#{lambda_config['role']}", 'Arn'))
          Property('Runtime', lambda_config['runtime'])
          Property('Timeout', timeout)
          if (lambda_config['vpc'] != nil && lambda_config['vpc'])
            Property('VpcConfig', {
                SubnetIds: config['availability_zones'].collect { |az| Ref("SubnetPrivate#{az}") },
                SecurityGroupIds: [Ref('SecurityGroupBackplane')]
            })
          end

          if(lambda_config['named'] != nil && lambda_config['named'])
            Property('FunctionName',name)
          end

        end

        sha256 = lambda_config['code_sha256']
        Resource("#{name}Version#{lambda_config['timestamp']}") do
          Type 'AWS::Lambda::Version'
          DeletionPolicy 'Retain'
          Property('FunctionName',Ref(name))
          Property('CodeSha256', sha256)
        end

        if lambda_config['allowed_sources'] != nil
          i = 1
          lambda_config['allowed_sources'].each do |source|
            Resource("#{name}Permissions#{i}") do
              Type 'AWS::Lambda::Permission'
              Property('FunctionName',Ref(name))
              Property('Action','lambda:InvokeFunction')
              Property('Principal',source['principal'])
            end
            i = i+1
          end
        end

        Output("Function#{name}") {
          Value(Ref(name))
        }

      end

    end
  end

end

if defined? lambdas
  lambdas = Lambdas.new(config)
  lambdas.create_stack()
end

