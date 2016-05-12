require 'cfndsl'
require_relative '../../ext/helper'

if !defined? timezone
  timezone = 'GMT'
end

image = 'fabric8/hawtio'
java_opts = ''
memory = 1024
cpu = 300
container_port = 0
service = lookup_service('hawtio', services)
if service
  java_opts = service['JAVA_OPTS'] || java_opts
  image = service['ContainerImage'] || image
  memory = service['ContainerMemory'] || memory
  cpu = service['ContainerCPU'] || cpu
  container_port = service['InstancePort'] || container_port
end

CloudFormation {

  AWSTemplateFormatVersion "2010-09-09"
  Description "ciinabox - ECS Service Hawtio v#{ciinabox_version}"

  Parameter("ECSCluster"){ Type 'String' }
  Parameter("ECSRole"){ Type 'String' }
  Parameter("ServiceELB"){ Type 'String' }

  Resource('HawtioTask') {
    Type "AWS::ECS::TaskDefinition"
    Property('ContainerDefinitions', [
      {
        Name: 'hawtio',
        Memory: memory,
        Cpu: cpu,
        Image: image,
        Environment: [
          {
            Name: 'JAVA_OPTS',
            Value: "#{java_opts} -Duser.timezone=#{timezone}"
          },
          {
            Name: 'VIRTUAL_HOST',
            Value: "hawtio.#{dns_domain}"
          },
          {
            Name: 'VIRTUAL_PORT',
            Value: '8080'
          },
          {
            Name: 'hawtio_dirname',
            Value: '/var/hawtio'
          },

        ],
        Essential: true,
        MountPoints: [
          {
            ContainerPath: '/etc/localtime',
            SourceVolume: 'timezone',
            ReadOnly: true
          },
          {
            ContainerPath: '/var/hawtio',
            SourceVolume: 'data',
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
        Name: 'data',
        Host: {
          SourcePath: '/data/hawtio'
        }
      }
    ])
  }

  Resource('HawtioService') {
    Type 'AWS::ECS::Service'
    Property('Cluster', Ref('ECSCluster'))
    Property('DesiredCount', 1)
    Property('TaskDefinition', Ref('HawtioTask'))
    Property('Role', Ref('ECSRole')) unless container_port == 0
    Property('LoadBalancers', [
      { ContainerName: 'hawtio', ContainerPort: container_port, LoadBalancerName: Ref('ServiceELB') }
    ]) unless container_port == 0

  }
}
