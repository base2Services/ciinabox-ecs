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
  ecs_parameters = {
      ECSCluster: Ref(cluster_name),
      VPC: FnGetAtt('VPCStack', 'Outputs.VPCId'),
      SecurityGroupBackplane: FnGetAtt('VPCStack', 'Outputs.SecurityGroupBackplane')
  }

  maximum_availability_zones.times do |az|
    ecs_parameters["RouteTablePrivate#{az}"] = FnGetAtt('VPCStack', "Outputs.RouteTablePrivate#{az}")
    ecs_parameters["SubnetPublic#{az}"] = FnGetAtt('VPCStack', "Outputs.RouteTablePrivate#{az}")
  end

  Resource('ECSStack') {
    Type 'AWS::CloudFormation::Stack'
    Property('TemplateURL', "https://#{source_bucket}.s3.amazonaws.com/ciinabox/#{ciinabox_version}/ecs-cluster.json")
    Property('TimeoutInMinutes', 5)
    Property('Parameters', ecs_parameters)
  }

  # ECS Services Stack
  ecs_services_params={
      ECSCluster: Ref(cluster_name),
      VPC: FnGetAtt('VPCStack', 'Outputs.VPCId'),
      SecurityGroupBackplane: FnGetAtt('VPCStack', 'Outputs.SecurityGroupBackplane'),
      SecurityGroupOps: FnGetAtt('VPCStack', 'Outputs.SecurityGroupOps'),
      SecurityGroupDev: FnGetAtt('VPCStack', 'Outputs.SecurityGroupDev')
  }

  maximum_availability_zones.times do |az|
    ecs_services_params["SubnetPublic#{az}"] = FnGetAtt('VPCStack', "Outputs.SubnetPublic#{az}")
    ecs_services_params["ECSSubnetPrivate#{az}"] = FnGetAtt('ECSStack', "Outputs.ECSSubnetPrivate#{az}")
  end

  Resource('ECSServicesStack') {
    Type 'AWS::CloudFormation::Stack'
    Property('TemplateURL', "https://#{source_bucket}.s3.amazonaws.com/ciinabox/#{ciinabox_version}/ecs-services.json")
    Property('TimeoutInMinutes', 5)
    Property('Parameters', ecs_services_params)
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

  maximum_availability_zones.times do |az|
    base_params.merge!("SubnetPublic#{az}" => FnGetAtt('VPCStack', "Outputs.SubnetPublic#{az}"))
    base_params.merge!("RouteTablePrivate#{az}" => FnGetAtt('VPCStack', "Outputs.RouteTablePrivate#{az}"))
  end

  #Foreign templates
  #e.g CIINABOXES_DIR/CIINABOX/templates/x.rb
  #for f in foreign templates do:
  #  new stack
  if defined? extra_stacks
    extra_stacks.each do |stack, details|

      #Note: each time we use base_params we need to clone
      #assignment for hash is a shalow copy
      #we could also use z = Hash[x] or  Marshal.load(Marshal.dump(original_hash))
      #also add any params from the config
      params = base_params.clone
      params.merge! details["parameters"] if details["parameters"]

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

  maximum_availability_zones.times do |az|
    Output("PublicSubnet#{az}") {
      Value(FnGetAtt('VPCStack', "Outputs.SubnetPublic#{az}"))
    }
  end

  maximum_availability_zones.times do |az|
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

end
