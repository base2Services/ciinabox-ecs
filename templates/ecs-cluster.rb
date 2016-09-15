require 'cfndsl'

volume_name = "ECSDataVolume"
if defined? ecs_data_volume_name
  volume_name = ecs_data_volume_name
end

volume_size = 100
if defined? ecs_data_volume_size
  volume_size = ecs_data_volume_size
end

CloudFormation {

  # Template metadata
  AWSTemplateFormatVersion "2010-09-09"
  Description "ciinabox - ECS Cluster v#{ciinabox_version}"

  # Parameters
  Parameter("ECSCluster"){ Type 'String' }
  Parameter("VPC"){ Type 'String' }
  Parameter("RouteTablePrivateA"){ Type 'String' }
  Parameter("RouteTablePrivateB"){ Type 'String' }
  Parameter("SubnetPublicA"){ Type 'String' }
  Parameter("SubnetPublicB"){ Type 'String' }
  Parameter("SecurityGroupBackplane"){ Type 'String' }

  # Global mappings
  Mapping('EnvironmentType', Mappings['EnvironmentType'])
  Mapping('ecsAMI', ecs_ami)

  availability_zones.each do |az|
    Resource("SubnetPrivate#{az}") {
      Type 'AWS::EC2::Subnet'
      Property('VpcId', Ref('VPC'))
      Property('CidrBlock', FnJoin( "", [ FnFindInMap('EnvironmentType','ciinabox','NetworkPrefix'), ".", FnFindInMap('EnvironmentType','ciinabox','StackOctet'), ".", ecs["SubnetOctet#{az}"], ".0/", FnFindInMap('EnvironmentType','ciinabox','SubnetMask') ] ))
      Property('AvailabilityZone', FnSelect(azId[az], FnGetAZs(Ref( "AWS::Region" )) ))
    }
  end

  availability_zones.each do |az|
    Resource("SubnetRouteTableAssociationPrivate#{az}") {
      Type 'AWS::EC2::SubnetRouteTableAssociation'
      Property('SubnetId', Ref("SubnetPrivate#{az}"))
      Property('RouteTableId', Ref("RouteTablePrivate#{az}"))
    }
  end

  Resource("Role") {
    Type 'AWS::IAM::Role'
    Property('AssumeRolePolicyDocument', {
      Statement: [
        Effect: 'Allow',
        Principal: { Service: [ 'ec2.amazonaws.com' ] },
        Action: [ 'sts:AssumeRole' ]
      ]
    })
    Property('Path','/')
    Property('Policies', [
      {
        PolicyName: 'assume-role',
        PolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Action: [ 'sts:AssumeRole' ],
              Resource: '*'
            }
          ]
        }
      },
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
                "elasticloadbalancing:RegisterInstancesWithLoadBalancer"
              ],
              Resource: '*'
            }
          ]
        }
      },
      {
        'PolicyName' => 'ssm-run-command',
        'PolicyDocument' => {
          'Statement' => [
            {
              'Effect' => 'Allow',
              'Action' => [
                "ssm:DescribeAssociation",
                "ssm:GetDocument",
                "ssm:ListAssociations",
                "ssm:UpdateAssociationStatus",
                "ssm:UpdateInstanceInformation",
                "ec2messages:AcknowledgeMessage",
                "ec2messages:DeleteMessage",
                "ec2messages:FailMessage",
                "ec2messages:GetEndpoint",
                "ec2messages:GetMessages",
                "ec2messages:SendReply",
                "cloudwatch:PutMetricData",
                "ec2:DescribeInstanceStatus",
                "ds:CreateComputer",
                "ds:DescribeDirectories",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "logs:PutLogEvents",
                "s3:PutObject",
                "s3:GetObject",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts",
                "s3:ListBucketMultipartUploads"
              ],
              'Resource' => '*'
            }
          ]
        }
      },
      {
        PolicyName: 'ecr',
        PolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Action: [
                'ecr:*'
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
                'cloudformation:*',
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
		            'ec2:GetPasswordData',
                'iam:PassRole',
                'dynamodb:*'
              ],
              Resource: '*'
            }
          ]
        }
      }
    ])
  }

  InstanceProfile("InstanceProfile") {
    Path '/'
    Roles [ Ref('Role') ]
  }

  Volume(volume_name) {
    DeletionPolicy 'Snapshot'
    Size volume_size
    VolumeType 'gp2'
    if defined? ecs_data_volume_snapshot
      SnapshotId ecs_data_volume_snapshot
    end
    AvailabilityZone FnSelect(0, FnGetAZs(""))
    addTag("Name", "ciinabox-ecs-data-xx")
    addTag("Environment", 'ciinabox')
    addTag("EnvironmentType", 'ciinabox')
    addTag("Role", "ciinabox-data")
    addTag("MakeSnapshot", "true")
  }

  LaunchConfiguration( :LaunchConfig ) {
    ImageId FnFindInMap('ecsAMI',Ref('AWS::Region'),'ami')
    IamInstanceProfile Ref('InstanceProfile')
    KeyName FnFindInMap('EnvironmentType','ciinabox','KeyName')
    SecurityGroups [ Ref('SecurityGroupBackplane') ]
    InstanceType FnFindInMap('EnvironmentType','ciinabox','ECSInstanceType')
    if defined? ecs_docker_volume_size and ecs_docker_volume_size > 22
      Property("BlockDeviceMappings", [
        {
          "DeviceName" => "/dev/xvdcz",
          "Ebs" => {
            "VolumeSize" => ecs_docker_volume_size,
            "VolumeType" => "gp2"
          }
        }])
    end
    UserData FnBase64(FnJoin("",[
      "#!/bin/bash\n",
      "echo ECS_CLUSTER=", Ref('ECSCluster'), " >> /etc/ecs/ecs.config\n",
      "INSTANCE_ID=`/opt/aws/bin/ec2-metadata -i | cut -f2 -d: | cut -f2 -d-`\n",
      "PRIVATE_IP=`/opt/aws/bin/ec2-metadata -o | cut -f2 -d: | cut -f2 -d-`\n",
      "yum install -y python-pip\n",
      "python-pip install --upgrade awscli\n",
      "/usr/local/bin/aws --region ", Ref("AWS::Region"), " ec2 attach-volume --volume-id ", Ref(volume_name), " --instance-id i-${INSTANCE_ID} --device /dev/sdf\n",
      "echo 'waiting for ECS Data volume to attach' && sleep 20\n",
      "echo '/dev/xvdf   /data        ext4    defaults,nofail 0   2' >> /etc/fstab\n",
      "mkdir -p /data\n",
      "mount /data && echo \"ECS Data volume already formatted\" || mkfs -t ext4 /dev/xvdf\n",
      "mount -a && echo 'mounting ECS Data volume' || echo 'failed to mount ECS Data volume'\n",
      "export BOOTSTRAP=/data/bootstrap \n",
      "if [ ! -e \"$BOOTSTRAP\" ]; then echo \"boostrapping\"; chmod -R 777 /data; mkdir -p /data/jenkins; chown -R 1000:1000 /data/jenkins;  touch $BOOTSTRAP; fi \n",
      "ifconfig eth0 mtu 1500\n",
      "curl https://amazon-ssm-", Ref("AWS::Region"),".s3.amazonaws.com/latest/linux_amd64/amazon-ssm-agent.rpm -o /tmp/amazon-ssm-agent.rpm\n",
      "yum install -y /tmp/amazon-ssm-agent.rpm\n",
      "stop ecs\n",
      "service docker stop\n",
      "service docker start\n",
      "start ecs\n",
      "docker run --name jenkins-docker-slave --privileged=true -d -e PORT=4444 -p 4444:4444 -p 2223:22 -v /data/jenkins-dind/:/var/lib/docker base2/ciinabox-dind-slave\n",
      "echo 'done!!!!'\n"
    ]))
  }

  AutoScalingGroup("AutoScaleGroup") {
    UpdatePolicy("AutoScalingRollingUpdate", {
      "MinInstancesInService" => "0",
      "MaxBatchSize"          => "1",
    })
    LaunchConfigurationName Ref('LaunchConfig')
    HealthCheckGracePeriod '500'
    MinSize 1
    MaxSize 1
    DesiredCapacity 1
    VPCZoneIdentifier [ Ref('SubnetPrivateA') ]
    addTag("Name", FnJoin("",["ciinabox-ecs-xx"]), true)
    addTag("Environment",'ciinabox', true)
    addTag("EnvironmentType", 'ciinabox', true)
    addTag("Role", "ciinabox-ecs", true)
  }

  if defined? scale_up_schedule
    Resource("ScheduledActionUp") {
      Type 'AWS::AutoScaling::ScheduledAction'
      Property('AutoScalingGroupName', Ref('AutoScaleGroup'))
      Property('MinSize','1')
      Property('MaxSize', '1')
      Property('DesiredCapacity', '1')
      Property('Recurrence', scale_up_schedule)
    }
  end

  if defined? scale_down_schedule
    Resource("ScheduledActionDown") {
      Type 'AWS::AutoScaling::ScheduledAction'
      Property('AutoScalingGroupName', Ref('AutoScaleGroup'))
      Property('MinSize','0')
      Property('MaxSize', '0')
      Property('DesiredCapacity', '0')
      Property('Recurrence', scale_down_schedule)
    }
  end

  availability_zones.each do |az|
    Output("ECSSubnetPrivate#{az}") {
      Value(Ref("SubnetPrivate#{az}"))
    }
  end

  Output("ECSRole") {
    Value(Ref('Role'))
  }

  Output("ECSInstanceProfile") {
    Value(Ref('InstanceProfile'))
  }

}
