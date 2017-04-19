require 'cfndsl'

class Lambdas

  def initialize

  end

  def create_stack(ciinabox_name, lambdas, lambdaSubnets, availability_zones, azId,
      mappings,
      ciinabox_version)

    ciinaboxes_dir = ENV['CIINABOXES_DIR'] || 'ciinaboxes'

    CloudFormation do

      # Template metadata
      AWSTemplateFormatVersion "2010-09-09"
      Description "ciinabox - Lambda Functions -v #{ciinabox_version}"

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

      Mapping('EnvironmentType', mappings['EnvironmentType'])

      ## Subnets for Lambdas
      availability_zones.each do |az|
        Resource("SubnetPrivate#{az}") {
          Type 'AWS::EC2::Subnet'
          Property('VpcId', Ref('VPC'))
          Property('CidrBlock', FnJoin("", [FnFindInMap('EnvironmentType', 'ciinabox', 'NetworkPrefix'), ".", FnFindInMap('EnvironmentType', 'ciinabox', 'StackOctet'), ".", lambdaSubnets["SubnetOctet#{az}"], ".0/", FnFindInMap('EnvironmentType', 'ciinabox', 'SubnetMask')]))
          Property('AvailabilityZone', FnSelect(azId[az], FnGetAZs(Ref("AWS::Region"))))
          Property('Tags', [{ Key: 'Name', Value: "ciinabox-lambda-private-#{az}" }])
        }
      end

      availability_zones.each do |az|
        Resource("SubnetRouteTableAssociationPrivate#{az}") {
          Type 'AWS::EC2::SubnetRouteTableAssociation'
          Property('SubnetId', Ref("SubnetPrivate#{az}"))
          Property('RouteTableId', Ref("RouteTablePrivate#{az}"))
        }
      end

      lambdas['roles'].each do |lambda_role, role_config|
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


      lambdas['functions'].each do |name, lambda_config|
        timeout = lambda_config['timeout'] != nil ? lambda_config['timeout'] : 10
        memory = lambda_config['memory'] != nil ? lambda_config['memory'] : 128
        code = IO.read("#{ciinaboxes_dir}/#{ciinabox_name}/#{lambda_config['code']}")
        environment = lambda_config['environment'] != nil ? lambda_config['environment'] : {}
        Resource(name) do
          Type 'AWS::Lambda::Function'
          Property('Code', {
              ZipFile: code
          })
          Property('Environment', {
              Variables: Hash[environment.collect { |k, v| [k.upcase, v] }]
          })
          Property('Handler', 'index.handler')
          Property('MemorySize', memory)
          Property('Role', FnGetAtt("LambdaRole#{lambda_config['role']}", 'Arn'))
          Property('Runtime', lambda_config['runtime'])
          Property('Timeout', timeout)
          if (lambda_config['vpc'] != nil && lambda_config['vpc'])
            Property('VpcConfig', {
                SubnetIds: availability_zones.collect { |az| Ref("SubnetPrivate#{az}") },
                SecurityGroupIds: [Ref('SecurityGroupBackplane')]
            })
          end

          if(lambda_config['named'] != nil && lambda_config['named'])
            Property('FunctionName',name)
          end

        end

        Output("Function#{name}") {
          Value(Ref(name))
        }

      end

    end
  end

end

def create_stack_lambdas()

end

if defined? lambdas
  Lambdas.new.create_stack(ciinabox_name, lambdas, lambdaSubnets, availability_zones, azId,Mappings, ciinabox_version)
end

