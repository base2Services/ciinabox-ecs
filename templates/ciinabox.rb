CloudFormation do
  # Default params
  cluster_name ||= 'ciinabox'
  source_bucket ||= 'ciinabox_demo'

  # Template metadata
  AWSTemplateFormatVersion '2010-09-09'
  Description 'Ciinabox ECS - Master'

  Resource(cluster_name) {
    Type 'AWS::ECS::Cluster'
  }

  # VPC Stack
  Resource('VPCStack') {
    Type 'AWS::CloudFormation::Stack'
    Property('TemplateURL', FnJoin('', ['https://s3-', Ref('AWS::Region'), ".amazonaws.com/#{source_bucket}/ciinabox/#{ciinabox_version}/vpc.json"]))
    Property('TimeoutInMinutes', 5)
    Property('Parameters',
      EnvironmentType: Ref('EnvironmentType'),
      DNSDomain: Ref('DNSDomain')
    )
  }

end
