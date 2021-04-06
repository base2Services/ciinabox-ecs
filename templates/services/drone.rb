require 'cfndsl'
require 'securerandom'
require 'deep_merge'
require_relative '../../ext/helper'

# default values
shared_envs = {
  TZ: "Australia/Melbourne",
  DRONE_SECRET: SecureRandom.hex
}
drone_server_envs = shared_envs.clone
drone_server_envs.deep_merge!({
  DRONE_HOST: "https://drone.#{dns_domain}"
})
drone_agent_envs = shared_envs.clone
drone_agent_envs.deep_merge!({
  DRONE_SERVER: {
    "Fn::Join" => [
      ":",
      [
        { Ref: "ECSENIPrivateIpAddress" },
        "9000"
      ]
    ]
  }
})
internal_drone_elb = true
drone_server_image = 'drone/drone'
drone_agent_image = 'drone/agent'
drone_server_ext_ports = [ '8000' ]
drone_server_int_ports = [ '9000' ]
drone_server_mappings = []
drone_agent_mappings = []
drone_params = [
  { VPC: { Ref: "VPC" } },
  { SubnetPublicA: { Ref: "SubnetPublicA" } },
  { SubnetPublicB: { Ref: "SubnetPublicB" } },
  { ECSSubnetPrivateA: { Ref: "ECSSubnetPrivateA" } },
  { ECSSubnetPrivateB: { Ref: "ECSSubnetPrivateB"} },
  { SecurityGroupBackplane: { Ref: "SecurityGroupBackplane" } },
  { SecurityGroupOps: { Ref: "SecurityGroupOps" } },
  { SecurityGroupDev: { Ref: "SecurityGroupDev" } },
  { SecurityGroupNatGateway: { Ref: "SecurityGroupNatGateway" } },
  { SecurityGroupWebHooks: { Ref: "SecurityGroupWebHooks" } },
  { ECSENIPrivateIpAddress: { Ref: "ECSENIPrivateIpAddress" } }
]

# resource allocations
memory = 512
cpu = 256

# look up service
service = lookup_service('drone', services)

if service and service['params'].kind_of?(Array)
  drone_params = drone_params | service['params']
end

if service and service['tasks']
  tasks = service['tasks']
  if not tasks['drone-server'].nil?
    # drone-server envs
    drone_server_envs.deep_merge!(tasks['drone-server']['env'])
    # drone-server docker images
    drone_server_image = tasks['drone-server']['image'] || drone_server_image
    # drone-server ports
    drone_server_ext_ports = tasks['drone-server']['ext-ports'] || drone_server_ext_ports
    drone_server_int_ports = tasks['drone-server']['int-ports'] || drone_server_int_ports
    # drone-server mappings
    drone_server_mappings = tasks['drone-server']['mappings'] || drone_server_mappings
  end

  if not tasks['drone-agent'].nil?
    # drone-agent envs
    drone_agent_envs.deep_merge!(tasks['drone-agent']['env'])
    # drone-agent docker images
    drone_agent_image = tasks['drone-agent']['image'] || drone_agent_image
    # drone-agent mappings
    drone_agent_mappings = tasks['drone-agent']['mappings'] || drone_agent_mappings
  end

  # internal elb
  internal_drone_elb = tasks['internal_drone_elb'] || internal_drone_elb
end

# dictionaries
envs = {
  'drone-server' => drone_server_envs,
  'drone-agent' => drone_agent_envs
}

images = {
  'drone-server' => drone_server_image,
  'drone-agent' => drone_agent_image
}

ext_ports = {
  'drone-server' => drone_server_ext_ports
}

int_ports = {
  'drone-server' => drone_server_int_ports
}

mappings = {
  'drone-server' => drone_server_mappings,
  'drone-agent' => drone_agent_mappings
}

# defined ecs volumes
volumes = [
  {
    Name: 'timezone',
    Host: {
      SourcePath: '/etc/localtime'
    }
  },
  {
    Name: 'drone_data',
    Host: {
      SourcePath: '/data/drone'
    }
  },
  {
    Name: 'docker_socket',
    Host: {
      SourcePath: '/var/run/docker.sock'
    }
  }
]

# mounts
mounts = {
  'drone-server' => [
    {
        ContainerPath: '/etc/localtime',
        SourceVolume: 'timezone',
        ReadOnly: true
    },
    {
        ContainerPath: '/var/lib/drone',
        SourceVolume: 'drone_data',
        ReadOnly: false
    }
  ],
  'drone-agent' => [
    {
        ContainerPath: '/etc/localtime',
        SourceVolume: 'timezone',
        ReadOnly: true
    },
    {
      ContainerPath: '/var/run/docker.sock',
      SourceVolume: 'docker_socket',
      ReadOnly: false
    }
  ]
}

# generate container definition
container_definitions = {}

['drone-server', 'drone-agent'].each do | task |
  definition = (service && service['tasks']) ? (service['tasks'][task] || {}) : {}
  container_definition = [{
    Name: task,
    Links: [],
    Memory: definition['memory'] || memory,
    Cpu: definition['cpu'] || cpu,
    Image: images[task],
    PortMappings: ((ext_ports[task] || []) | (int_ports[task] || [])).map { |mapping|
      t = mapping.split(':')
      if t.length >= 2
        {
          ContainerPort: t[1].to_i,
          HostPort: t[0].to_i
        }.merge(t[2] ? {Protocol: t[2]} : {})
      elsif t.length == 1
        {
          ContainerPort: t[0].to_i
        }
      end
    }.compact,
    Essential: true,
    MountPoints: mounts[task],
    Environment: envs[task].map { |key, value|
      {
        Name: key,
        Value: value
      }
    }
  }]
  container_definitions.merge!(task => container_definition)
end

# Cloudformation
CloudFormation {

  AWSTemplateFormatVersion "2010-09-09"
  Description "ciinabox - ECS Service Drone v#{ciinabox_version}"

  Parameter("ECSCluster") {Type 'String'}
  Parameter("ECSRole") {Type 'String'}
  Parameter("ServiceELB") {Type 'String'}
  Parameter('InternalELB') {Type 'String'} if internal_elb

  drone_params.each do |param|
    param.keys.each do |key|
      Parameter(key) {Type 'String'}
    end
  end

  # Mapping
  Mapping('EnvironmentType', Mappings['EnvironmentType'])

  drone_alb_sg = [Ref("SecurityGroupBackplane"), Ref("SecurityGroupOps"), Ref("SecurityGroupDev"), Ref("SecurityGroupNatGateway"), Ref("SecurityGroupWebHooks")]

  Resource('DroneServerALB') {
    Type "AWS::ElasticLoadBalancingV2::LoadBalancer"
    Property("SecurityGroups", drone_alb_sg)
    Property("Subnets", [Ref("SubnetPublicA"), Ref("SubnetPublicB")])
    Property("Tags", [
      { Key: "Name", Value: "DroneServerALB Application LoadBalancer" }
    ])
  }

  Resource('DroneServerALBTargetGroup') {
    DependsOn("DroneServerALB")
    Type "AWS::ElasticLoadBalancingV2::TargetGroup"
    Property("HealthCheckPath", '/')
    Property("HealthCheckProtocol", 'HTTP')
    Property("HealthCheckIntervalSeconds", 30)
    Property("HealthCheckTimeoutSeconds", 10)
    Property("HealthyThresholdCount", 3)
    Property("UnhealthyThresholdCount", 2)
    Property("Matcher", {
      HttpCode: "200,302,301"
    })
    Property("Port", 8000)
    Property("Protocol", 'HTTP')
    Property("VpcId", Ref("VPC"))
    Property("Tags",[
      { Key: "Name", Value: "DroneServerALB Target Group" },
    ])
  }

  Resource("DroneServerALBHTTPListener") {
    DependsOn("DroneServerALB")
    DependsOn("DroneServerALBTargetGroup")
    Type "AWS::ElasticLoadBalancingV2::Listener"
    Property("Protocol", "HTTP")
    Property("Port", 80)
    Property("DefaultActions", [
      TargetGroupArn: Ref("DroneServerALBTargetGroup"),
      Type: "forward"
    ])
    Property("LoadBalancerArn", Ref("DroneServerALB"))
  }

  Resource("DroneServerALBHTTPSListener") {
    DependsOn("DroneServerALB")
    DependsOn("DroneServerALBTargetGroup")
    Type "AWS::ElasticLoadBalancingV2::Listener"
    Property("Certificates", [{CertificateArn: default_ssl_cert_id}])
    Property("Protocol", "HTTPS")
    Property("Port", 443)
    Property("DefaultActions", [
      TargetGroupArn: Ref("DroneServerALBTargetGroup"),
      Type: "forward"
    ])
    Property("LoadBalancerArn", Ref("DroneServerALB"))
  }

  # Resource("SecurityGroupDroneNLB") {
  #   Type 'AWS::EC2::SecurityGroup'
  #   Property('VpcId', Ref('VPC'))
  #   Property('GroupDescription', 'DRONE NLB SG')
  #   Property('SecurityGroupIngress', [
  #     { IpProtocol: 'tcp', FromPort: '9000', ToPort: '9000', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType','ciinabox','NetworkPrefix'),".", FnFindInMap('EnvironmentType','ciinabox','StackOctet'), ".0.0/",FnFindInMap('EnvironmentType','ciinabox','StackMask') ] ) }
  #   ])
  # }
  #
  # drone_nlb_sg = [Ref("SecurityGroupDroneNLB")]
  #
  # Resource('DroneServerNLB') {
  #   Type "AWS::ElasticLoadBalancingV2::LoadBalancer"
  #   Property("Scheme", "internal")
  #   Property("Type", "network")
  #   # Property("SecurityGroups", drone_nlb_sg)
  #   Property("Subnets", [
  #     Ref("ECSSubnetPrivateA"),
  #     Ref("ECSSubnetPrivateB")
  #   ])
  #   Property("Tags", [
  #     { Key: "Name", Value: "DroneServerNLB Network LoadBalancer" }
  #   ])
  # }
  #
  # Resource('DroneServerNLBTargetGroup') {
  #   DependsOn("DroneServerNLB")
  #   Type "AWS::ElasticLoadBalancingV2::TargetGroup"
  #   Property("HealthCheckProtocol", 'TCP')
  #   Property("HealthCheckPort", 9000)
  #   Property("HealthCheckIntervalSeconds", 30)
  #   Property("HealthCheckTimeoutSeconds", 10)
  #   Property("HealthyThresholdCount", 3)
  #   Property("UnhealthyThresholdCount", 3)
  #   Property("Port", 9000)
  #   Property("Protocol", 'TCP')
  #   Property("VpcId", Ref("VPC"))
  #   Property("Tags",[
  #     { Key: "Name", Value: "DroneServerNLB Target Group" },
  #   ])
  # }
  #
  # Resource("DroneServerNLBListener") {
  #   DependsOn("DroneServerNLB")
  #   DependsOn("DroneServerNLBTargetGroup")
  #   Type "AWS::ElasticLoadBalancingV2::Listener"
  #   Property("Protocol", "TCP")
  #   Property("Port", 9000)
  #   Property("DefaultActions", [
  #     TargetGroupArn: Ref("DroneServerNLBTargetGroup"),
  #     Type: "forward"
  #   ])
  #   Property("LoadBalancerArn", Ref("DroneServerNLB"))
  # }

  Resource('DroneServerTask') {
    Type "AWS::ECS::TaskDefinition"
    Property('ContainerDefinitions', container_definitions['drone-server'])
    Property('NetworkMode', 'host')
    Property('Volumes', volumes)
  }

  Resource('DroneAgentTask') {
    Type "AWS::ECS::TaskDefinition"
    Property('ContainerDefinitions', container_definitions['drone-agent'])
    Property('NetworkMode', 'host')
    Property('Volumes', volumes)
  }

  drone_server_lbs = []

  Resource('DroneServerService') {
    Type 'AWS::ECS::Service'
    Property('Cluster', Ref('ECSCluster'))
    Property('DeploymentConfiguration', {
        MaximumPercent: 100,
        MinimumHealthyPercent: 0
    })
    Property('DesiredCount', 1)
    Property('TaskDefinition', Ref('DroneServerTask'))
    Property('Role', Ref('ECSRole'))
    Property('LoadBalancers', (ext_ports['drone-server'] || []).map { |mapping|
      t = mapping.split(':')
      if t.length >= 2
        {
          ContainerName: 'drone-server',
          ContainerPort: t[1].to_i,
          TargetGroupArn: Ref('DroneServerALBTargetGroup')
        }
      else
        {
          ContainerName: 'drone-server',
          ContainerPort: t[0].to_i,
          TargetGroupArn: Ref('DroneServerALBTargetGroup')
        }
      end
    })
  }

  Resource('DroneAgentService') {
    Type 'AWS::ECS::Service'
    DependsOn('DroneServerService')
    Property('Cluster', Ref('ECSCluster'))
    Property('DeploymentConfiguration', {
        MaximumPercent: 100,
        MinimumHealthyPercent: 0
    })
    Property('DesiredCount', 1)
    Property('TaskDefinition', Ref('DroneAgentTask'))
  }

  Resource("DroneServerDNS") {
    Type 'AWS::Route53::RecordSet'
    Property('HostedZoneName', FnJoin('', [ dns_domain, '.']))
    Property('Name', FnJoin('', ['drone.', dns_domain, '.']))
    Property('Type','A')
    Property('AliasTarget', {
      'DNSName' => FnGetAtt('DroneServerALB','DNSName'),
      'HostedZoneId' => FnGetAtt('DroneServerALB','CanonicalHostedZoneID')
    })
  }
}
