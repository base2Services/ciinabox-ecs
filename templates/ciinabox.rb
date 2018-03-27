require_relative '../ext/policies'

CloudFormation do

  # Template metadata
  AWSTemplateFormatVersion '2010-09-09'
  Description "ciinabox ECS - Master v#{ciinabox_version}"

  Resource(cluster_name) {
    Type 'AWS::ECS::Cluster'
  }

  # VPC Stack
  Resource('VPCStack') {
    Type 'AWS::CloudFormation::Stack'
    Property('TemplateURL', "https://#{source_bucket}.s3.amazonaws.com/ciinabox/#{ciinabox_version}/vpc.json")
    Property('TimeoutInMinutes', 10)
  }

  # ECS Cluster Stack
  Resource('ECSStack') {
    Type 'AWS::CloudFormation::Stack'
    Property('TemplateURL', "https://#{source_bucket}.s3.amazonaws.com/ciinabox/#{ciinabox_version}/ecs-cluster.json")
    Property('TimeoutInMinutes', 10)
    Property('Parameters',{
      ECSCluster: Ref(cluster_name),
      VPC: FnGetAtt('VPCStack', 'Outputs.VPCId'),
      RouteTablePrivateA: FnGetAtt('VPCStack', 'Outputs.RouteTablePrivateA'),
      RouteTablePrivateB: FnGetAtt('VPCStack', 'Outputs.RouteTablePrivateB'),
      SubnetPublicA: FnGetAtt('VPCStack', 'Outputs.SubnetPublicA'),
      SubnetPublicB: FnGetAtt('VPCStack', 'Outputs.SubnetPublicB'),
      SecurityGroupBackplane: FnGetAtt('VPCStack', 'Outputs.SecurityGroupBackplane')
    })
  }

  # ECS Services Stack
  Resource('ECSServicesStack') {
    Type 'AWS::CloudFormation::Stack'
    Property('TemplateURL', "https://#{source_bucket}.s3.amazonaws.com/ciinabox/#{ciinabox_version}/ecs-services.json")
    Property('TimeoutInMinutes', 15)
    Property('Parameters',{
      ECSCluster: Ref(cluster_name),
      VPC: FnGetAtt('VPCStack', 'Outputs.VPCId'),
      SubnetPublicA: FnGetAtt('VPCStack', 'Outputs.SubnetPublicA'),
      SubnetPublicB: FnGetAtt('VPCStack', 'Outputs.SubnetPublicB'),
      ECSSubnetPrivateA: FnGetAtt('ECSStack', 'Outputs.ECSSubnetPrivateA'),
      ECSSubnetPrivateB: FnGetAtt('ECSStack', 'Outputs.ECSSubnetPrivateB'),
      ECSENIPrivateIpAddress: FnGetAtt('ECSStack', 'Outputs.ECSENIPrivateIpAddress'),
      SecurityGroupBackplane: FnGetAtt('VPCStack', 'Outputs.SecurityGroupBackplane'),
      SecurityGroupOps: FnGetAtt('VPCStack', 'Outputs.SecurityGroupOps'),
      SecurityGroupDev: FnGetAtt('VPCStack', 'Outputs.SecurityGroupDev'),
      SecurityGroupNatGateway: FnGetAtt('VPCStack', 'Outputs.SecurityGroupNatGateway'),
      CRAcmCertArn: FnGetAtt('LambdasStack','Outputs.LambdaCRIssueACMCertificateArn')
    })
  }

  #These are the commona params for use below in "foreign templates
  base_params = {
    VPC: FnGetAtt('VPCStack', 'Outputs.VPCId'),
    SecurityGroupBackplane: FnGetAtt('VPCStack', 'Outputs.SecurityGroupBackplane'),
    SecurityGroupOps: FnGetAtt('VPCStack', 'Outputs.SecurityGroupOps'),
    SecurityGroupDev: FnGetAtt('VPCStack', 'Outputs.SecurityGroupDev'),
    EnvironmentType: 'ciinabox',
    EnvironmentName: 'ciinabox'
  }

  availability_zones.each do |az|
    base_params.merge!("SubnetPublic#{az}" => FnGetAtt('VPCStack', "Outputs.SubnetPublic#{az}"))
    base_params.merge!("RouteTablePrivate#{az}" => FnGetAtt('VPCStack', "Outputs.RouteTablePrivate#{az}"))
  end

  # Lambda functions stack
  Resource('LambdasStack') do
    Type 'AWS::CloudFormation::Stack'
    Property('TemplateURL', "https://#{source_bucket}.s3.amazonaws.com/ciinabox/#{ciinabox_version}/lambdas.json")
    Property('Parameters', base_params)
  end


  # Bastion if required
  Resource('BastionStack') do
    Type 'AWS::CloudFormation::Stack'
    Property('TemplateURL', "https://#{source_bucket}.s3.amazonaws.com/ciinabox/#{ciinabox_version}/bastion.json")
    Property('Parameters', base_params)
  end if include_bastion_stack



  #Foreign templates
  #e.g CIINABOXES_DIR/CIINABOX/templates/x.rb
  #for f in foreign templates do:
  #  new stack

  if defined? extra_stacks
    extra_stacks.each do | stack, details |

      #Note: each time we use base_params we need to clone
      #assignment for hash is a shalow copy
      #we could also use z = Hash[x] or  Marshal.load(Marshal.dump(original_hash))
      #also add any params from the config
      params = base_params.clone
      params.merge!details["parameters"] if details["parameters"]

      #if file_name not applied assume stack name = file_name
      file_name = details["file_name"] ? details["file_name"] : stack

      Resource(stack) {
        Type 'AWS::CloudFormation::Stack'
        Property('TemplateURL', "https://#{source_bucket}.s3.amazonaws.com/ciinabox/#{ciinabox_version}/#{file_name}.json")
        Property('Parameters', params)
      }

      if details['outputs']
        details['outputs'].each do |output|
          Output(output) {
            Value(FnGetAtt(stack, "Outputs.#{output}"))
          }
        end
      end
    end
  end

  Output("Region") {
    Value(Ref('AWS::Region'))
  }

  Output("VPCId") {
    Value(FnGetAtt('VPCStack', 'Outputs.VPCId'))
  }

  availability_zones.each do |az|
    Output("PublicSubnet#{az}") {
      Value(FnGetAtt('VPCStack', "Outputs.SubnetPublic#{az}"))
    }
  end

  availability_zones.each do |az|
    Output("ECSPrivateSubnet#{az}") {
      Value(FnGetAtt('ECSStack', "Outputs.ECSSubnetPrivate#{az}"))
    }
  end

  Output("SecurityGroup") {
    Value(FnGetAtt('VPCStack', 'Outputs.SecurityGroupBackplane'))
  }

  Output("ECSRole") {
    Value(FnGetAtt('ECSStack', 'Outputs.ECSRole'))
  }

  Output("ECSInstanceProfile") {
    Value(FnGetAtt('ECSStack', 'Outputs.ECSInstanceProfile'))
  }

  Output('DefaultSSLCertificate'){
    Value(FnGetAtt('ECSServicesStack','Outputs.DefaultSSLCertificate'))
  }

end
