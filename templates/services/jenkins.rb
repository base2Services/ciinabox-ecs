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
virtual_host = "jenkins.#{dns_domain}"
port_mappings = []

if service
  jenkins_java_opts = service['JAVA_OPTS'] || ''
  image = service['ContainerImage'] || 'base2/ciinabox-jenkins'
  memory = service['ContainerMemory'] || 2048
  cpu = service['ContainerCPU'] || 300

  if service['InstancePort']
    container_port = service['InstancePort']
    virtual_host = "jenkins.#{dns_domain},internal-jenkins.#{dns_domain}"
    port_mappings = [{
          HostPort: 50000,
          ContainerPort: 50000
        }]
  end
end

CloudFormation {

  AWSTemplateFormatVersion "2010-09-09"
  Description "ciinabox - ECS Service Jenkins v#{ciinabox_version}"

  Parameter("ECSCluster"){ Type 'String' }
  Parameter("ECSRole"){ Type 'String' }
  Parameter("ServiceELB"){ Type 'String' }
  Parameter('InternalELB'){ Type 'String'} if internal_elb

  Resource('JenkinsTask') {
    Type "AWS::ECS::TaskDefinition"
    Property('ContainerDefinitions', [
      {
        Name: 'jenkins',
        Memory: memory,
        Cpu: cpu,
        Image: image,
        PortMappings: port_mappings,
        Environment: [
          {
            Name: 'JAVA_OPTS',
            Value: "#{jenkins_java_opts} -Duser.timezone=#{timezone}"
          },
          {
            Name: 'VIRTUAL_HOST',
            Value: virtual_host
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
    #For Role... Conditional. This parameter is required only if you specify the LoadBalancers property.
    Property('Role', Ref('ECSRole')) if internal_elb and container_port != 0
    Property('LoadBalancers', [
      { ContainerName: 'jenkins', ContainerPort: container_port, LoadBalancerName: Ref('InternalELB') }
    ]) if internal_elb and container_port != 0

  }
}
