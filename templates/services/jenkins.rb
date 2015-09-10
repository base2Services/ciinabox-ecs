require 'cfndsl'

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
        Memory: 2024,
        Cpu: 300,
        Image: 'base2/ciinabox-jenkins',
        PortMappings: [{
          HostPort: 8080,
          ContainerPort: 8080
        }],
        Environment: [{
          Name: 'JAVA_OPTS',
          Value: '-Duser.timezone=America/Los_Angeles'
        }],
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
    Property('Role', Ref('ECSRole'))
    Property('TaskDefinition', Ref('JenkinsTask'))
    Property('LoadBalancers', [
      { ContainerName: 'jenkins', ContainerPort: '8080', LoadBalancerName: Ref('ServiceELB') }
    ])
  }
}
