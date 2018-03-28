require 'cfndsl'
require_relative '../../ext/helper'

if !defined? timezone
  timezone = 'GMT'
end

image = 'base2/ciinabox-artifactory:5.9.3'
java_opts = ''
memory = 1024
cpu = 0
container_port = 0
service = lookup_service('artifactory', services)
if service
  service = {} if service.nil?
  java_opts = service['JAVA_OPTS'] || ''
  image = service['ContainerImage'] || image
  memory = service['ContainerMemory'] || memory
  cpu = service['ContainerCPU'] || cpu
  container_port = service['InstancePort'] || 0
end

CloudFormation {

  AWSTemplateFormatVersion "2010-09-09"
  Description "ciinabox - ECS Service Artifactory v#{ciinabox_version}"

  Parameter("ECSCluster"){ Type 'String' }
  Parameter("ECSRole"){ Type 'String' }
  Parameter("ServiceELB"){ Type 'String' }

  Resource('ArtifactoryTask') {
    Type "AWS::ECS::TaskDefinition"
    Property('ContainerDefinitions', [
      {
        Name: 'artifactory',
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
            Value: "artifactory.#{dns_domain}"
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
            ContainerPath: '/var/opt/jfrog/artifactory/data',
            SourceVolume: 'artifactory_data',
            ReadOnly: false
          },
            {
                ContainerPath: '/var/opt/jfrog/artifactory/etc',
                SourceVolume: 'artifactory_etc',
                ReadOnly: false
            },
            {
                ContainerPath: '/var/opt/jfrog/artifactory/logs',
                SourceVolume: 'artifactory_logs',
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
        Name: 'artifactory_data',
        Host: {
          SourcePath: '/data/artifactory/data'
        }
      },
      {
          Name: 'artifactory_etc',
          Host: {
              SourcePath: '/data/artifactory/etc'
          }
      },
      {
          Name: 'artifactory_logs',
          Host: {
              SourcePath: '/data/artifactory/logs'
          }
      }
    ])
  }

  Resource('ArtifactoryService') {
    Type 'AWS::ECS::Service'
    Property('Cluster', Ref('ECSCluster'))
    Property('DesiredCount', 1)
    Property('TaskDefinition', Ref('ArtifactoryTask'))
    Property('Role', Ref('ECSRole')) unless container_port == 0
    Property('LoadBalancers', [
      { ContainerName: 'artifactory', ContainerPort: container_port, LoadBalancerName: Ref('ServiceELB') }
    ]) unless container_port == 0

  }

}
