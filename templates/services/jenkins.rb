require 'cfndsl'

if !defined? timezone
  timezone = 'GMT'
end

if !defined? internal_elb
  internal_elb = nil
end

if !defined? volatile_jenkins_slave
  volatile_jenkins_slave = false
end

# Prefixing application images allows us to 'vendorize' ciinabox into client's account by setting
# ciinabox_repo to ${account_no}.dkr.ecr.${region}.amazonaws.com
if not defined? ciinabox_repo
  ciinabox_repo=''
end

image = "#{ciinabox_repo}base2/ciinabox-jenkins:2"

jenkins_java_opts = ''
memory = 2048
cpu = 300
container_port = 0
service = lookup_service('jenkins', services)
virtual_host = "jenkins.#{dns_domain}"
if defined? internal_elb and internal_elb
  virtual_host = "#{virtual_host},internal-jenkins.#{dns_domain}"
end
port_mappings = []

if service
  jenkins_java_opts = service['JAVA_OPTS'] || ''
  image = service['ContainerImage'] || image
  memory = service['ContainerMemory'] || 2048
  cpu = service['ContainerCPU'] || 300

  if service['InstancePort']
    port_mappings << {
        HostPort: service['InstancePort'],
        ContainerPort: service['InstancePort']
    }
    container_port = service['InstancePort']
    virtual_host = "jenkins.#{dns_domain},internal-jenkins.#{dns_domain}"
  end

end

# container volumes and container definitions depending on feature flags
volumes = [
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
    }]

container_definitions = [
    {
        Name: 'jenkins',
        Links: [],
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
]

# If docker in docker slave is enabled
if defined? include_diind_slave and include_diind_slave
  container_definitions[0][:Links] << 'jenkins-docker-dind-slave'
  dind_definition = {
      Name: 'jenkins-docker-dind-slave',
      Memory: service['SlaveContainerMemory'] || 2048,
      Image: "#{ciinabox_repo}base2/ciinabox-docker-slave:#{docker_slave_version}",
      Environment: [{Name: 'RUN_DOCKER_IN_DOCKER', Value: 1}],
      Essential: false,
      Privileged: true
  }
  dind_definition[:Environment] << { Name: 'USE_ECR_CREDENTIAL_HELPER', Value: 1 } if docker_slave_enable_ecr_credentials_helper
  if not volatile_jenkins_slave
    dind_definition[:MountPoints] = [
        {
            ContainerPath: '/var/lib/docker',
            SourceVolume: 'jenkins_dind_data',
            ReadOnly: false
        }
    ]
    volumes << {
        Name: 'jenkins_dind_data',
        Host: {
            SourcePath: '/data/jenkins-diind'
        }
    }
  end
  container_definitions << dind_definition

end

# If docker outside of docker slave is enabled
if defined? include_dood_slave and include_dood_slave
  container_definitions[0][:Links] << 'jenkins-docker-dood-slave'
  dood_definition =  {
      Name: 'jenkins-docker-dood-slave',
      Memory: service['SlaveContainerMemory'] || 2048,,
      Image: "#{ciinabox_repo}base2/ciinabox-docker-slave:#{docker_slave_version}",
      Environment: [{Name: 'RUN_DOCKER_IN_DOCKER', Value: 0}],
      MountPoints: [
          {
              ContainerPath: '/var/run/docker.sock',
              SourceVolume: 'docker_socket',
              ReadOnly: false
          },
          {
              ContainerPath: '/data/jenkins-dood',
              SourceVolume: 'jenkins_dood_data',
              ReadOnly: false
          }
      ],
      Essential: false,
      Privileged: false
  }
  dood_definition[:Environment] << { Name: 'USE_ECR_CREDENTIAL_HELPER', Value: 1 } if docker_slave_enable_ecr_credentials_helper
  container_definitions << dood_definition
  volumes << {
      Name: 'jenkins_dood_data',
      Host: {
          SourcePath: '/data/jenkins-dood'
      }
  }
  volumes << {
      Name: 'docker_socket',
      Host: {
          SourcePath: '/var/run/docker.sock'
      }
  }
end


CloudFormation {

  AWSTemplateFormatVersion "2010-09-09"
  Description "ciinabox - ECS Service Jenkins v#{ciinabox_version}"

  Parameter("ECSCluster") {Type 'String'}
  Parameter("ECSRole") {Type 'String'}
  Parameter("ServiceELB") {Type 'String'}
  Parameter('InternalELB') {Type 'String'} if internal_elb

  Resource('JenkinsTask') {
    Type "AWS::ECS::TaskDefinition"
    Property('ContainerDefinitions', container_definitions)
    Property('Volumes', volumes)
  }

  Resource('JenkinsService') {
    Type 'AWS::ECS::Service'
    Property('Cluster', Ref('ECSCluster'))
    Property('DeploymentConfiguration', {
        MaximumPercent: 100,
        MinimumHealthyPercent: 0
    })
    Property('DesiredCount', 1)
    Property('TaskDefinition', Ref('JenkinsTask'))
    #For Role... Conditional. This parameter is required only if you specify the LoadBalancers property.
    Property('Role', Ref('ECSRole')) if internal_elb and container_port != 0
    Property('LoadBalancers', [
        {ContainerName: 'jenkins', ContainerPort: container_port, LoadBalancerName: Ref('InternalELB')}
    ]) if internal_elb and container_port != 0
  }
}
