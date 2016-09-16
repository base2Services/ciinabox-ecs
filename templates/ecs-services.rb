require 'cfndsl'

CloudFormation {

  # Template metadata
  AWSTemplateFormatVersion "2010-09-09"
  Description "ciinabox - ECS Services v#{ciinabox_version}"

  # Parameters
  Parameter("ECSCluster"){ Type 'String' }
  Parameter("VPC"){ Type 'String' }
  Parameter("SubnetPublicA"){ Type 'String' }
  Parameter("SubnetPublicB"){ Type 'String' }
  Parameter("ECSSubnetPrivateA"){ Type 'String' }
  Parameter("ECSSubnetPrivateB"){ Type 'String' }
  Parameter("SecurityGroupBackplane"){ Type 'String' }
  Parameter("SecurityGroupOps"){ Type 'String' }
  Parameter("SecurityGroupDev"){ Type 'String' }

  Resource("ECSRole") {
    Type 'AWS::IAM::Role'
    Property('AssumeRolePolicyDocument', {
      Statement: [
        Effect: 'Allow',
        Principal: { Service: [ 'ecs.amazonaws.com' ] },
        Action: [ 'sts:AssumeRole' ]
      ]
    })
    Property('Path','/')
    Property('Policies', [
      {
        PolicyName: 'read-only',
        PolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Action: [ 'ec2:Describe*', 's3:Get*', 's3:List*'],
              Resource: '*'
            }
          ]
        }
      },
      {
        PolicyName: 's3-write',
        PolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Action: [ 's3:PutObject', 's3:PutObject*' ],
              Resource: '*'
            }
          ]
        }
      },
      #http://docs.aws.amazon.com/AmazonECS/latest/developerguide/instance_IAM_role.html
      {
        PolicyName: 'ecsServiceRole',
        PolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Action: [
                "ecs:CreateCluster",
                "ecs:DeregisterContainerInstance",
                "ecs:DiscoverPollEndpoint",
                "ecs:Poll",
                "ecs:RegisterContainerInstance",
                "ecs:StartTelemetrySession",
                "ecs:Submit*",
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:Describe*",
                "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
                "elasticloadbalancing:Describe*",
                "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
              ],
              Resource: '*'
            }
          ]
        }
      },
      {
        PolicyName: 'packer',
        PolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Action: [
                'ec2:AttachVolume',
                'ec2:CreateVolume',
                'ec2:DeleteVolume',
                'ec2:CreateKeypair',
                'ec2:DeleteKeypair',
                'ec2:CreateSecurityGroup',
                'ec2:DeleteSecurityGroup',
                'ec2:AuthorizeSecurityGroupIngress',
                'ec2:CreateImage',
                'ec2:RunInstances',
                'ec2:TerminateInstances',
                'ec2:StopInstances',
                'ec2:DescribeVolumes',
                'ec2:DetachVolume',
                'ec2:DescribeInstances',
                'ec2:CreateSnapshot',
                'ec2:DeleteSnapshot',
                'ec2:DescribeSnapshots',
                'ec2:DescribeImages',
                'ec2:RegisterImage',
                'ec2:CreateTags',
                'ec2:ModifyImageAttribute',
                'dynamodb:*'
              ],
              Resource: '*'
            }
          ]
        }
      }
    ])
  }

  if defined? webHooks
    rules = []
    webHooks.each do |ip|
      rules << { IpProtocol: 'tcp', FromPort: '443', ToPort: '443', CidrIp: ip }
    end
  else
    rules = [{IpProtocol: 'tcp', FromPort: '443', ToPort: '443', CidrIp: '192.168.1.1/32'}]
  end

  Resource("SecurityGroupWebHooks") {
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', 'WebHooks like github')
    Property('SecurityGroupIngress', rules)
  }

  elb_listners = []
  elb_listners << { LoadBalancerPort: '80', InstancePort: '8080', Protocol: 'HTTP' }
  elb_listners << { LoadBalancerPort: '443', InstancePort: '8080', Protocol: 'HTTPS', SSLCertificateId: default_ssl_cert_id  }
  services.each do |service|
    if service.is_a?(Hash) && ( !service.values.include? nil )
      service.each do |name, properties|
        unless properties['LoadBalancerPort'].nil? || properties['InstancePort'].nil? || properties['Protocol'].nil?
          elb_listners << { LoadBalancerPort: properties['LoadBalancerPort'], InstancePort: properties['InstancePort'], Protocol: properties['Protocol'] }
        end
      end
    end
  end

  Resource('CiinaboxProxyELB') {
    Type 'AWS::ElasticLoadBalancing::LoadBalancer'
    Property('Listeners', elb_listners)
    Property('HealthCheck', {
      Target: "TCP:8080",
      HealthyThreshold: '3',
      UnhealthyThreshold: '2',
      Interval: '15',
      Timeout: '5'
    })
    Property('CrossZone',true)
    Property('SecurityGroups',[
      Ref('SecurityGroupBackplane'),
      Ref('SecurityGroupOps'),
      Ref('SecurityGroupDev'),
      Ref('SecurityGroupWebHooks')
    ])
    Property('Subnets',[
      Ref('SubnetPublicA'),Ref('SubnetPublicB')
    ])
  }

  Resource("CiinaboxProxyDNS") {
    Type 'AWS::Route53::RecordSet'
    Property('HostedZoneName', FnJoin('', [ dns_domain, '.']))
    Property('Name', FnJoin('', ['*.', dns_domain, '.']))
    Property('Type','A')
    Property('AliasTarget', {
      'DNSName' => FnGetAtt('CiinaboxProxyELB','DNSName'),
      'HostedZoneId' => FnGetAtt('CiinaboxProxyELB','CanonicalHostedZoneNameID')
    })
  }

  if defined? internal_elb and internal_elb
    Resource('CiinaboxProxyELBInternal') {
      Type 'AWS::ElasticLoadBalancing::LoadBalancer'
      Property('Listeners', elb_listners)
      Property('Scheme', 'internal')
      Property('HealthCheck', {
        Target: "TCP:8080",
        HealthyThreshold: '3',
        UnhealthyThreshold: '2',
        Interval: '15',
        Timeout: '5'
      })
      Property('CrossZone',true)
      Property('SecurityGroups',[
        Ref('SecurityGroupBackplane'),
        Ref('SecurityGroupOps'),
        Ref('SecurityGroupDev'),
        Ref('SecurityGroupWebHooks')
      ])
      Property('Subnets',[
        Ref('ECSSubnetPrivateA'),Ref('ECSSubnetPrivateB')
      ])
    }

    services.each do |service|
        #Services look like this:
        #[
        # {\"jenkins\"=>{\"LoadBalancerPort\"=>50000, \"InstancePort\"=>50000, \"Protocol\"=>\"TCP\"}}",
        # {\"bitbucket\"=>{\"LoadBalancerPort\"=>22, \"InstancePort\"=>7999, \"Protocol\"=>\"TCP\"}}"
        #]
        name, details = service.first
        Resource("CiinaboxProxyDNSInternal") {
          Type 'AWS::Route53::RecordSet'
          Property('HostedZoneName', FnJoin('', [ dns_domain, '.']))
          Property('Name', FnJoin('', ["internal-#{name}.", dns_domain, '.']))
          Property('Type','A')
          Property('AliasTarget', {
            'DNSName' => FnGetAtt('CiinaboxProxyELBInternal','DNSName'),
            'HostedZoneId' => FnGetAtt('CiinaboxProxyELB','CanonicalHostedZoneNameID')
          })
        }
    end
  end

  Resource('ProxyTask') {
    Type "AWS::ECS::TaskDefinition"
    Property('ContainerDefinitions', [
      {
        Name: 'proxy',
        Memory: 256,
        Cpu: 100,
        Image: 'jwilder/nginx-proxy',
        PortMappings: [{
          HostPort: 8080,
          ContainerPort: 80
        }],
        Essential: true,
        MountPoints: [
          {
            ContainerPath: '/etc/localtime',
            SourceVolume: 'timezone',
            ReadOnly: true
          },
          {
            ContainerPath: '/tmp/docker.sock',
            SourceVolume: 'docker_sock',
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
        Name: 'docker_sock',
        Host: {
          SourcePath: '/var/run/docker.sock'
        }
      }
    ])
  }

  Resource('ProxyService') {
    Type 'AWS::ECS::Service'
    Property('Cluster', Ref('ECSCluster'))
    Property('DesiredCount', 1)
    Property('Role', Ref('ECSRole'))
    Property('TaskDefinition', Ref('ProxyTask'))
    Property('LoadBalancers', [
      { ContainerName: 'proxy', ContainerPort: '80', LoadBalancerName: Ref('CiinaboxProxyELB') }
    ])
  }

  services.each do |name|
    name.each do |service_name, service|
      params = {
        ECSCluster: Ref('ECSCluster'),
        ECSRole: Ref('ECSRole'),
        ServiceELB: Ref('CiinaboxProxyELB')
      }
      params['InternalELB'] = Ref('CiinaboxProxyELBInternal') if defined? internal_elb and internal_elb
      # ECS Task Def and Service  Stack
      Resource("#{service_name}Stack") {
        Type 'AWS::CloudFormation::Stack'
        Property('TemplateURL', "https://#{source_bucket}.s3.amazonaws.com/ciinabox/#{ciinabox_version}/services/#{service_name}.json")
        Property('TimeoutInMinutes', 5)
        Property('Parameters', params)
      }
    end
  end
}
