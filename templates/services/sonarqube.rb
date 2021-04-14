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
  postgres_url_param_arn = service['PostgresUrlParamArn'] || nil
  postgres_user_param_arn = service['PostgresUserParamArn'] || nil
  postgres_password_param_arn = service['PostgresPasswordParamArn'] || nil
end

CloudFormation {

  AWSTemplateFormatVersion "2010-09-09"
  Description "ciinabox - ECS Service SonarQube v#{ciinabox_version}"

  Parameter("ECSCluster"){ Type 'String' }
  Parameter("ECSRole"){ Type 'String' }
  Parameter("ServiceELB"){ Type 'String' }

  Resource('SonarQubeTask') {
    Type "AWS::ECS::TaskDefinition"
    Property('ExecutionRoleArn', FnGetAtt('TaskExecutionRole', 'Arn'))
    sonarqube_container_def = {
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
    if postgres_user_param_arn then
      sonarqube_container_def[:Secrets] = [
        {
          Name: 'SONARQUBE_JDBC_URL',
          ValueFrom: postgres_url_param_arn
        },
        {
          Name: 'SONARQUBE_JDBC_USERNAME',
          ValueFrom: postgres_user_param_arn
        },
        {
          Name: 'SONARQUBE_JDBC_PASSWORD',
          ValueFrom: postgres_password_param_arn
        }
      ]
    end
    Property('ContainerDefinitions', [sonarqube_container_def])
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

  Resource('TaskExecutionRole') {
    Type 'AWS::IAM::Role'
    Property('AssumeRolePolicyDocument', {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "Service": "ecs-tasks.amazonaws.com"
          },
          "Action": "sts:AssumeRole"
        }
      ]
    })
    Property('ManagedPolicyArns', [
      'arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess',
      'arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy'
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
