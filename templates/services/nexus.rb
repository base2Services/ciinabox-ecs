require 'cfndsl'
require_relative '../../ext/helper'

if !defined? timezone
  timezone = 'GMT'
end

image = 'base2/ciinabox-nexus'
container_path = '/sonatype-work'
java_opts = ''
memory = 1024
cpu = 300
container_port = 0
service = lookup_service('nexus', services)
if service
  java_opts = service['JAVA_OPTS'] || ''
  image = service['ContainerImage'] || image
  container_path = service['ContainerPath'] || container_path
  memory = service['ContainerMemory'] || 1024
  cpu = service['ContainerCPU'] || 300
  container_port = service['InstancePort'] || 0
end

CloudFormation {

  AWSTemplateFormatVersion "2010-09-09"
  Description "ciinabox - ECS Service Nexus v#{ciinabox_version}"

  Parameter("ECSCluster"){ Type 'String' }
  Parameter("ECSRole"){ Type 'String' }
  Parameter("ServiceELB"){ Type 'String' }

  Resource('NexusTask') {
    Type "AWS::ECS::TaskDefinition"
    Property('ContainerDefinitions', [
      {
        Name: 'nexus',
        Memory: memory,
        Cpu: cpu,
        Image: image,
        Environment: [
          {
            Name: 'JAVA_OPTS',
            Value: "#{java_opts} -Duser.timezone=#{timezone} -server -Djava.net.preferIPv4Stack=true"
          },
          {
            Name: 'VIRTUAL_HOST',
            Value: "nexus.#{dns_domain}"
          },
          {
            Name: 'VIRTUAL_PORT',
            Value: '8081'
          }
        ],
        Essential: true,
        MountPoints: [
          {
            ContainerPath: '/etc/localtime',
            SourceVolume: 'timezone',
            ReadOnly: true
          },
          {
            ContainerPath: container_path,
            SourceVolume: 'nexus_data',
            ReadOnly: false
          }
        ]
      }
    ])
    Property('Volumes', [
      {
        Name: 'timezone',
        Host: {
          SourcePath: '/etc/localtime'
        }
      },
      {
        Name: 'nexus_data',
        Host: {
          SourcePath: '/data/nexus'
        }
      }
    ])
  }

  Resource('NexusService') {
    Type 'AWS::ECS::Service'
    Property('Cluster', Ref('ECSCluster'))
    Property('DesiredCount', 1)
    Property('TaskDefinition', Ref('NexusTask'))
    Property('Role', Ref('ECSRole')) unless container_port == 0
    Property('LoadBalancers', [
      { ContainerName: 'nexus', ContainerPort: container_port, LoadBalancerName: Ref('ServiceELB') }
    ]) unless container_port == 0

  }

}
