CloudFormation do

  # Template metadata
  AWSTemplateFormatVersion '2010-09-09'
  Description "ciinabox - Vpn v#{ciinabox_version}"

  # Parameters
  Parameter('EnvironmentType'){ Type 'String' }
  Parameter('EnvironmentName'){ Type 'String' }
  Parameter('VPC'){ Type 'String' }
  Parameter('RouteTablePrivateA'){ Type 'String' }
  Parameter('RouteTablePrivateB'){ Type 'String' }
  Parameter('SubnetPublicA'){ Type 'String' }
  Parameter('SubnetPublicB'){ Type 'String' }
  Parameter('SecurityGroupBackplane'){ Type 'String' }
  Parameter('SecurityGroupOps'){ Type 'String' }
  Parameter('SecurityGroupDev'){ Type 'String' }

  # Global mappings
  Mapping('EnvironmentType', Mappings['EnvironmentType'])
  Mapping('ecsAMI', ecs_ami)

  IAM_Role("Role") {
    AssumeRolePolicyDocument({
      Statement: [
        Effect: 'Allow',
        Principal: { Service: [ 'ec2.amazonaws.com' ] },
        Action: [ 'sts:AssumeRole' ]
      ]
    })
    Path '/'
    Policies([
      {
        PolicyName: 'read-only',
        PolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Action: [ 'autoscaling:Describe*', 'ec2:Describe*', 's3:Get*', 's3:List*'],
              Resource: '*'
            }
          ]
        }
      },
      {
        PolicyName: 'attach-ec2-volumes',
        PolicyDocument:  {
          Statement: [
            {
              Effect: 'Allow',
              Action: [ 'ec2:AttachVolume','ec2:CreateVolume', 'ec2:Describe*', 'ec2:DetachVolume' ],
              Resource: '*'
            }
          ]
        }
      },
      {
        PolicyName: 'AttachNetworkInterface',
        PolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Action: [ 'ec2:DescribeNetworkInterfaces', 'ec2:AttachNetworkInterface','ec2:AssociateAddress' ],
              Resource: '*'
            }
          ]
        }
      },
      {
        PolicyName: 'ECSServiceRole',
        PolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Action: [
                'ecs:CreateCluster',
                'ecs:DeregisterContainerInstance',
                'ecs:DiscoverPollEndpoint',
                'ecs:Poll',
                'ecs:RegisterContainerInstance',
                'ecs:StartTelemetrySession',
                'ecs:Submit*',
                'ec2:AuthorizeSecurityGroupIngress'
              ],
              Resource: '*'
            }
          ]
        }
      }
    ])
  }

  ECS_Cluster('CiinaboxVpn')

  InstanceProfile('InstanceProfile') {
    Path '/'
    Roles [ Ref('Role') ]
  }

  EC2_EIP('VpnIPAddress') {
    Domain 'vpc'
  }

  EC2_Volume("VpnVolume") {
    DeletionPolicy 'Snapshot'
    Size '10'
    VolumeType 'gp2'
    if defined? vpn_data_volume_snapshot
      SnapshotId vpn_data_volume_snapshot
    end
    AvailabilityZone FnSelect(0, FnGetAZs(""))
    addTag('Name', 'ciinabox-vpn-config-xx')
    addTag('Environment', 'ciinabox')
    addTag('EnvironmentType', 'ciinabox')
    addTag('shelvery:create_backup','true')
    addTag('shelvery:config:shelvery_keep_daily_backups', '7')
    addTag('shelvery:config:shelvery_keep_weekly_backups', '4')
    addTag('shelvery:config:shelvery_keep_monthly_backups', '12')
  }

  AutoScaling_LaunchConfiguration('LaunchConfig') {
    DependsOn ['VpnIPAddress']
    ImageId FnFindInMap('ecsAMI', Ref('AWS::Region'), 'ami')
    KeyName FnFindInMap('EnvironmentType', 'ciinabox', 'KeyName')
    AssociatePublicIpAddress true
    IamInstanceProfile Ref('InstanceProfile')
    SecurityGroups [ Ref('SecurityGroupDev'), Ref('SecurityGroupBackplane'), Ref('SecurityGroupOps') ]
    Property('InstanceType', vpnInstanceType)
    UserData FnBase64(FnJoin('',[
        "#!/bin/bash\n",
        "echo ECS_CLUSTER=", Ref('CiinaboxVpn'), " >> /etc/ecs/ecs.config\n",
        "INSTANCE_ID=$(echo `/opt/aws/bin/ec2-metadata -i | cut -f2 -d:`)\n",
        'export NEW_HOSTNAME=', Ref('EnvironmentName'),"-vpn-xx-`/opt/aws/bin/ec2-metadata --instance-id|/usr/bin/awk '{print $2}'`", "\n",
        "echo \"NEW_HOSTNAME=$NEW_HOSTNAME\" \n",
        "hostname $NEW_HOSTNAME\n",
        "sed -i \"s/^HOSTNAME=.*/HOSTNAME=$NEW_HOSTNAME/\" /etc/sysconfig/network\n",
        "/usr/local/bin/aws --region ", Ref("AWS::Region"), " ec2 attach-volume --volume-id ", Ref('VpnVolume'), " --instance-id ${INSTANCE_ID} --device /dev/sdf\n",
        "mkdir /data \n",
        "e2fsck -fy /dev/xvdb ; if [ $? -eq 8 ]; then mkfs.ext4 /dev/xvdb && mount /dev/xvdb /data; else mount /dev/xvdb /data && \\ \n",
        'aws --region ', Ref('AWS::Region'), ' ec2 associate-address --allocation-id ', FnGetAtt('VpnIPAddress','AllocationId') ," --instance-id ${INSTANCE_ID}\n",
    ]))
  }

  AutoScalingGroup('AutoScaleGroup') {
    UpdatePolicy('AutoScalingRollingUpdate', {
        'MinInstancesInService' => '0',
        'MaxBatchSize' => '1',
    })
    LaunchConfigurationName Ref('LaunchConfig')
    HealthCheckGracePeriod '500'
    HealthCheckType 'EC2'
    MinSize 1
    MaxSize 1
    VPCZoneIdentifier [ Ref('SubnetPublicA') ]
    addTag('Name', FnJoin('-',[Ref('EnvironmentName'), 'vpn' , 'xx']), true)
    addTag('Environment', Ref('EnvironmentName'), true)
    addTag('EnvironmentType', Ref('EnvironmentType'), true)
    addTag('Role', 'vpn', true)
  }

  Route53_RecordSet('VpnRecordSet') {
    DependsOn ['VpnIPAddress']
    HostedZoneName FnJoin('', [ dns_domain, '.' ])
    Comment 'Vpn record set'
    Name FnJoin('', [ 'ov.',  Ref('EnvironmentName') , '.', dns_domain, '.' ])
    Type 'A'
    TTL '60'
    ResourceRecords [  Ref('VpnIPAddress') ]
  }

  ECS_TaskDefinition('OpenVpnTask') {
    ContainerDefinitions([
      {
        Name: 'openvpn',
        MemoryReservation: '1024',
        Cpu: '1024',
        Image: 'base2/openvpn-as',
        Essential: true,
        MountPoints: [
          {
            ContainerPath: '/etc/localtime',
            SourceVolume: 'timezone',
            ReadOnly: true
          },
          {
            ContainerPath: '/config',
            SourceVolume: 'data',
            ReadOnly: false
          }
        ]
      }
    ])
    NetworkMode 'host'
    Volumes([
      {
        Name: 'timezone',
        Host: {
          SourcePath: '/etc/localtime'
        }
      },
      {
        Name: 'data',
        Host: {
          SourcePath: '/data'
        }
      }
    ])
  }

  ECS_Service('OpenVpnService') {
    Cluster Ref('CiinaboxVpn')
    DesiredCount 1
    TaskDefinition Ref('OpenVpnTask')
  }

end
