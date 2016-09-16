require 'cfndsl'
require_relative '../../ext/helper'

if !defined? timezone
  timezone = 'GMT'
end

#icinga2_image: AWS_ACCOUNT_ID.dkr.ecr.AWS_REGION/base2/icinga2:VERSION_TAG
image = icinga2_image

memory = 1024
cpu = 300
container_port = 0

CloudFormation {

  AWSTemplateFormatVersion "2010-09-09"
  Description "ciinabox - ECS Service Hawtio v#{ciinabox_version}"

  Parameter("ECSCluster"){ Type 'String' }
  Parameter("ECSRole"){ Type 'String' }
  Parameter("ServiceELB"){ Type 'String' }

  Resource('Icinga2Task') {
    Type "AWS::ECS::TaskDefinition"
    Property('ContainerDefinitions', [
      {
        Name: 'icinga2',
        Memory: memory,
        Cpu: cpu,
        Image: image,
        Environment: [
          {
            Name: 'VIRTUAL_HOST',
            Value: "icinga2.#{dns_domain}"
          },
          {
            Name: 'VIRTUAL_PORT',
            Value: '80'
          }

        ],
        Essential: true,
        MountPoints: [
          {
            ContainerPath: '/etc/localtime',
            SourceVolume: 'timezone',
            ReadOnly: true
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
      }

    ])
  }

  Resource('IcingaService') {
    Type 'AWS::ECS::Service'
    Property('Cluster', Ref('ECSCluster'))
    Property('DesiredCount', 1)
    Property('TaskDefinition', Ref('Icinga2Task'))
    Property('Role', Ref('ECSRole')) unless container_port == 0
    # Property('LoadBalancers', [
    #   { ContainerName: 'hawtio', ContainerPort: container_port, LoadBalancerName: Ref('ServiceELB') }
    # ]) unless container_port == 0

  }
}
