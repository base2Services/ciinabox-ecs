CloudFormation do

  # Template metadata
  AWSTemplateFormatVersion '2010-09-09'
  Description "Ciinabox ECS - Master v#{ciinabox_version}"

  Resource(cluster_name) {
    Type 'AWS::ECS::Cluster'
  }

  # VPC Stack
  Resource('VPCStack') {
    Type 'AWS::CloudFormation::Stack'
    Property('TemplateURL', FnJoin('', ['https://s3-', Ref('AWS::Region'), ".amazonaws.com/#{source_bucket}/ciinabox/#{ciinabox_version}/vpc.json"]))
    Property('TimeoutInMinutes', 5)
  }

  # ECS Cluster Stack
  Resource('ECSStack') {
    Type 'AWS::CloudFormation::Stack'
    Property('TemplateURL', FnJoin('', ['https://s3-', Ref('AWS::Region'), ".amazonaws.com/#{source_bucket}/ciinabox/#{ciinabox_version}/ecs-cluster.json"]))
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

end
