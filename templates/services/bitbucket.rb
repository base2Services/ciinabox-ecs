require 'cfndsl'
require_relative '../../ext/helper'

if !defined? timezone
  timezone = 'GMT'
end

image = 'atlassian/bitbucket-server'
memory = 2048
cpu = 300
container_port = 7999
service = lookup_service('jenkins', services)
if service
  image = service['ContainerImage'] || 'atlassian/bitbucket-server'
  memory = service['ContainerMemory'] || 2048
  cpu = service['ContainerCPU'] || 300
  container_port = service['InstancePort'] || 7999
end

CloudFormation {

  AWSTemplateFormatVersion "2010-09-09"
  Description "ciinabox - ECS Service Bitbucket v#{ciinabox_version}"

  Parameter("ECSCluster"){ Type 'String' }
  Parameter("ECSRole"){ Type 'String' }
  Parameter("ServiceELB"){ Type 'String' }

  Resource('BitbucketTask') {
    Type "AWS::ECS::TaskDefinition"
    Property('ContainerDefinitions', [
      {
        Name: 'bitbucket',
        Memory: memory,
        Cpu: cpu,
        Image: image,
        PortMappings: [{
          HostPort: container_port,
          ContainerPort: container_port
        }],
        Environment: [
          {
            Name: 'VIRTUAL_HOST',
            Value: "bitbucket.#{dns_domain}"
          },
          {
            Name: 'VIRTUAL_PORT',
            Value: '7990'
          }
        ],
        Essential: true,
        MountPoints: [
          {
            ContainerPath: '/var/atlassian/application-data/bitbucket',
            SourceVolume: 'bitbucket_data',
            ReadOnly: false
          }
        ]
      }
    ])
    Property('Volumes', [
      {
        Name: 'bitbucket_data',
        Host: {
          SourcePath: '/data/bitbucket'
        }
      }
    ])
  }

  Resource('BitbucketService') {
    Type 'AWS::ECS::Service'
    Property('Cluster', Ref('ECSCluster'))
    Property('DesiredCount', 1)
    Property('TaskDefinition', Ref('BitbucketTask'))
    Property('Role', Ref('ECSRole'))
    Property('LoadBalancers', [
      { ContainerName: 'bitbucket', ContainerPort: '7999', LoadBalancerName: Ref('ServiceELB') }
    ])
  }
}
