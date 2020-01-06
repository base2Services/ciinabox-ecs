require 'cfndsl'
require_relative '../../ext/helper'

if !defined? timezone
  timezone = 'GMT'
end

image = 'sonarqube:lts'
java_opts = ''
memory = 2048
cpu = 300
container_port = 0
service = lookup_service('sonarqube', services)
if service
  java_opts = service['JAVA_OPTS'] || ''
  image = service['ContainerImage'] || image
  memory = service['ContainerMemory'] || 2048
  cpu = service['ContainerCPU'] || 300
  container_port = service['InstancePort'] || 0
end

CloudFormation {

  AWSTemplateFormatVersion "2010-09-09"
  Description "ciinabox - ECS Service SonarQube v#{ciinabox_version}"

  Parameter("ECSCluster"){ Type 'String' }
  Parameter("ECSRole"){ Type 'String' }
  Parameter("ServiceELB"){ Type 'String' }

  Resource('SonarQubeTask') {
    Type "AWS::ECS::TaskDefinition"
    Property('ContainerDefinitions', [
      {
        Name: 'sonarqube',
        MemoryReservation: memory,
        Cpu: cpu,
        Image: image,
        Environment: [
          {
            Name: 'VIRTUAL_HOST',
            Value: "sonar.#{dns_domain}"
          },
          {
            Name: 'VIRTUAL_PORT',
            Value: '9000'
          }
        ],
        Ulimits: [
          {
            Name: "nofile",
            SoftLimit: 65536,
            HardLimit: 65536
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
            ContainerPath: '/opt/sonarqube/extensions',
            SourceVolume: 'sonarqube_extensions',
            ReadOnly: false
          },
          {
            ContainerPath: '/opt/sonarqube/logs',
            SourceVolume: 'sonarqube_logs',
            ReadOnly: false
          },
          {
            ContainerPath: '/opt/sonarqube/data',
            SourceVolume: 'sonarqube_data',
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
        Name: 'sonarqube_conf',
        Host: {
          SourcePath: '/data/sonarqube/conf'
        }
      },
      {
        Name: 'sonarqube_extensions',
        Host: {
          SourcePath: '/data/sonarqube/extensions'
        }
      },
      {
        Name: 'sonarqube_logs',
        Host: {
          SourcePath: '/data/sonarqube/logs'
        }
      },
      {
        Name: 'sonarqube_data',
        Host: {
          SourcePath: '/data/sonarqube/data'
        }
      }
    ])
  }

  Resource('SonarQubeService') {
    Type 'AWS::ECS::Service'
    Property('Cluster', Ref('ECSCluster'))
    Property('DesiredCount', 1)
    Property('TaskDefinition', Ref('SonarQubeTask'))
    Property('Role', Ref('ECSRole')) unless container_port == 0
    Property('LoadBalancers', [
      { ContainerName: 'sonarqube', ContainerPort: container_port, LoadBalancerName: Ref('ServiceELB') }
    ]) unless container_port == 0

  }

}
