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
    Property('TimeoutInMinutes', 5)
  }

  # ECS Cluster Stack
  Resource('ECSStack') {
    Type 'AWS::CloudFormation::Stack'
    Property('TemplateURL', "https://#{source_bucket}.s3.amazonaws.com/ciinabox/#{ciinabox_version}/ecs-cluster.json")
    Property('TimeoutInMinutes', 5)
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
    Property('TimeoutInMinutes', 5)
    Property('Parameters',{
      ECSCluster: Ref(cluster_name),
      VPC: FnGetAtt('VPCStack', 'Outputs.VPCId'),
      SubnetPublicA: FnGetAtt('VPCStack', 'Outputs.SubnetPublicA'),
      SubnetPublicB: FnGetAtt('VPCStack', 'Outputs.SubnetPublicB'),
      ECSSubnetPrivateA: FnGetAtt('ECSStack', 'Outputs.ECSSubnetPrivateA'),
      ECSSubnetPrivateB: FnGetAtt('ECSStack', 'Outputs.ECSSubnetPrivateB'),
      SecurityGroupBackplane: FnGetAtt('VPCStack', 'Outputs.SecurityGroupBackplane'),
      SecurityGroupOps: FnGetAtt('VPCStack', 'Outputs.SecurityGroupOps'),
      SecurityGroupDev: FnGetAtt('VPCStack', 'Outputs.SecurityGroupDev')
    })
  }

  #Foreign templates
  #for f in foreign templates do:
  #new stack f.stack_name, f.url_name, f.params, f.depends
  if extra_stacks
    extra_stacks.each do | stack, details |
      Resource(stack) {
        Type 'AWS::CloudFormation::Stack'
        Property('TemplateURL', "https://#{source_bucket}.s3.amazonaws.com/ciinabox/#{ciinabox_version}/#{stack}.json")
        Property('Parameters',{
          VPC: FnGetAtt('VPCStack', 'Outputs.VPCId'),
          SubnetPublicA: FnGetAtt('VPCStack', 'Outputs.SubnetPublicA'),
          SubnetPublicB: FnGetAtt('VPCStack', 'Outputs.SubnetPublicB'),
          SecurityGroupBackplane: FnGetAtt('VPCStack', 'Outputs.SecurityGroupBackplane'),
          SecurityGroupOps: FnGetAtt('VPCStack', 'Outputs.SecurityGroupOps'),
          SecurityGroupDev: FnGetAtt('VPCStack', 'Outputs.SecurityGroupDev'),
          RouteTablePrivateA: FnGetAtt('VPCStack', 'Outputs.RouteTablePrivateA'),
          RouteTablePrivateB: FnGetAtt('VPCStack', 'Outputs.RouteTablePrivateB'),
          EnvironmentType: 'ciinabox',
          EnvironmentName: 'ciinabox',
          RoleName: details['role']
        })
      }
    end
  end

end
