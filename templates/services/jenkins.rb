require 'cfndsl'
require_relative '../../ext/helper'

if !defined? timezone
  timezone = 'GMT'
end

image = 'base2/ciinabox-jenkins'
jenkins_java_opts = ''
memory = 2048
cpu = 300
container_port = 0
service = lookup_service('jenkins', services)
if service
  jenkins_java_opts = service['JAVA_OPTS'] || ''
  image = service['ContainerImage'] || 'base2/ciinabox-jenkins'
  memory = service['ContainerMemory'] || 2048
  cpu = service['ContainerCPU'] || 300
  container_port = service['InstancePort'] || 0
end

CloudFormation {

  AWSTemplateFormatVersion "2010-09-09"
  Description "ciinabox - ECS Service Jenkins v#{ciinabox_version}"

  Parameter("ECSCluster"){ Type 'String' }
  Parameter("ECSRole"){ Type 'String' }
  Parameter("ServiceELB"){ Type 'String' }

  Resource('JenkinsTask') {
    Type "AWS::ECS::TaskDefinition"
    Property('ContainerDefinitions', [
      {
        Name: 'jenkins',
        Memory: memory,
        Cpu: cpu,
        Image: image,
        Environment: [
          {
            Name: 'JAVA_OPTS',
            Value: "#{jenkins_java_opts} -Duser.timezone=#{timezone}"
          },
          {
            Name: 'VIRTUAL_HOST',
            Value: "jenkins.#{dns_domain}"
          },
          {
            Name: 'VIRTUAL_PORT',
            Value: '8080'
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
            ContainerPath: '/var/jenkins_home',
            SourceVolume: 'jenkins_data',
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
        Name: 'jenkins_data',
        Host: {
          SourcePath: '/data/jenkins'
        }
      }
    ])
  }

  Resource('JenkinsService') {
    Type 'AWS::ECS::Service'
    Property('Cluster', Ref('ECSCluster'))
    Property('DesiredCount', 1)
    Property('TaskDefinition', Ref('JenkinsTask'))
    Property('Role', Ref('ECSRole')) unless container_port == 0
    Property('LoadBalancers', [
      { ContainerName: 'jenkins', ContainerPort: container_port, LoadBalancerName: Ref('ServiceELB') }
    ]) unless container_port == 0

  }
}
