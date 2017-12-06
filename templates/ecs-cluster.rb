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
  Parameter("ECSCluster") {Type 'String'}
  Parameter("VPC") {Type 'String'}
  Parameter("RouteTablePrivateA") {Type 'String'}
  Parameter("RouteTablePrivateB") {Type 'String'}
  Parameter("SubnetPublicA") {Type 'String'}
  Parameter("SubnetPublicB") {Type 'String'}
  Parameter("SecurityGroupBackplane") {Type 'String'}


  # Global mappings
  Mapping('EnvironmentType', Mappings['EnvironmentType'])
  Mapping('ecsAMI', ecs_ami)

  availability_zones.each do |az|
    Resource("SubnetPrivate#{az}") {
      Type 'AWS::EC2::Subnet'
      Property('VpcId', Ref('VPC'))
      Property('CidrBlock', FnJoin("", [FnFindInMap('EnvironmentType', 'ciinabox', 'NetworkPrefix'), ".", FnFindInMap('EnvironmentType', 'ciinabox', 'StackOctet'), ".", ecs["SubnetOctet#{az}"], ".0/", FnFindInMap('EnvironmentType', 'ciinabox', 'SubnetMask')]))
      Property('AvailabilityZone', FnSelect(azId[az], FnGetAZs(Ref("AWS::Region"))))
    }
  end

  availability_zones.each do |az|
    Resource("SubnetRouteTableAssociationPrivate#{az}") {
      Type 'AWS::EC2::SubnetRouteTableAssociation'
      Property('SubnetId', Ref("SubnetPrivate#{az}"))
      Property('RouteTableId', Ref("RouteTablePrivate#{az}"))
    }
  end

  ecs_iam_role_permissions = ecs_iam_role_permissions_default
  if defined? ecs_iam_role_permissions_extras
    ecs_iam_role_permissions = ecs_iam_role_permissions + ecs_iam_role_permissions_extras
  end

  ecs_role_policies = ecs_iam_role_permissions.collect {|p|
    {
        PolicyName: p['name'],
        PolicyDocument: {
            Statement: [
                {
                    Effect: 'Allow',
                    Action: p['actions'],
                    Resource: p['resource'] || '*'
                }
            ]
        }
    }
  }

  has_ciinabox_role_predefined = defined? ciinabox_iam_role_name

  Resource("Role") {
    Type 'AWS::IAM::Role'
    Property('AssumeRolePolicyDocument', {
        Statement: [
            Effect: 'Allow',
            Principal: {Service: ['ec2.amazonaws.com']},
            Action: ['sts:AssumeRole']
        ]
    })
    Property('Path', '/')
    Property('Policies', ecs_role_policies)
  } unless has_ciinabox_role_predefined

  InstanceProfile("InstanceProfile") {
    Path '/'
    Roles [Ref('Role')] unless has_ciinabox_role_predefined
    Roles [ciinabox_iam_role_name] if has_ciinabox_role_predefined
  }

  EC2_Volume(volume_name) {
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

  ecs_block_device_mapping = []
  user_data_init_devices = ''
  if defined? ecs_root_volume_size and ecs_root_volume_size > 8
    ecs_block_device_mapping << {
        "DeviceName" => "/dev/xvda",
        "Ebs" => {
            "VolumeSize" => ecs_root_volume_size
        }
    }
  end

  if defined? ecs_docker_volume_size and ecs_docker_volume_size > 22
    ecs_block_device_mapping << {
        "DeviceName" => "/dev/xvdcz",
        "Ebs" => {
            "VolumeSize" => ecs_docker_volume_size,
            "VolumeType" => "gp2"
        }
    }
    if (defined? 'ecs_docker_volume_volumemount') and (binding.eval('ecs_docker_volume_volumemount') == true)
      user_data_init_devices = "mkfs.ext4 /dev/xvdcz && " +
                               "mount /dev/xvdcz /var/lib/docker\n"
    end
  end

  ecs_sgs = [Ref('SecurityGroupBackplane')]

  LaunchConfiguration(:LaunchConfig) {
    ImageId FnFindInMap('ecsAMI', Ref('AWS::Region'), 'ami')
    IamInstanceProfile Ref('InstanceProfile')
    KeyName FnFindInMap('EnvironmentType', 'ciinabox', 'KeyName')
    SecurityGroups ecs_sgs
    InstanceType FnFindInMap('EnvironmentType', 'ciinabox', 'ECSInstanceType')
    if not ecs_block_device_mapping.empty?
      Property("BlockDeviceMappings", ecs_block_device_mapping)
    end
    UserData FnBase64(FnJoin("", [
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
        "#{user_data_init_devices}",
        "export BOOTSTRAP=/data/bootstrap \n",
        "if [ ! -e \"$BOOTSTRAP\" ]; then echo \"boostrapping\"; chmod -R 777 /data; mkdir -p /data/jenkins; chown -R 1000:1000 /data/jenkins;  touch $BOOTSTRAP; fi \n",
        "ifconfig eth0 mtu 1500\n",
        "curl https://amazon-ssm-", Ref("AWS::Region"), ".s3.amazonaws.com/latest/linux_amd64/amazon-ssm-agent.rpm -o /tmp/amazon-ssm-agent.rpm\n",
        "yum install -y /tmp/amazon-ssm-agent.rpm\n",
        "stop ecs\n",
        "service docker stop\n",
        "service docker start\n",
        "start ecs\n",
        "echo 'done!!!!'\n"
    ]))
  }

  AutoScalingGroup("AutoScaleGroup") {
    UpdatePolicy("AutoScalingRollingUpdate", {
        "MinInstancesInService" => "0",
        "MaxBatchSize" => "1",
    })
    LaunchConfigurationName Ref('LaunchConfig')
    HealthCheckGracePeriod '500'
    MinSize 1
    MaxSize 1
    DesiredCapacity 1
    VPCZoneIdentifier [Ref('SubnetPrivateA')]
    addTag("Name", FnJoin("", ["ciinabox-ecs-xx"]), true)
    addTag("Environment", 'ciinabox', true)
    addTag("EnvironmentType", 'ciinabox', true)
    addTag("Role", "ciinabox-ecs", true)
  }

  if defined? scale_up_schedule
    Resource("ScheduledActionUp") {
      Type 'AWS::AutoScaling::ScheduledAction'
      Property('AutoScalingGroupName', Ref('AutoScaleGroup'))
      Property('MinSize', '1')
      Property('MaxSize', '1')
      Property('DesiredCapacity', '1')
      Property('Recurrence', scale_up_schedule)
    }
  end

  if defined? scale_down_schedule
    Resource("ScheduledActionDown") {
      Type 'AWS::AutoScaling::ScheduledAction'
      Property('AutoScalingGroupName', Ref('AutoScaleGroup'))
      Property('MinSize', '0')
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
    Value(Ref('Role')) unless has_ciinabox_role_predefined
    Value(ciinabox_iam_role_name) if has_ciinabox_role_predefined
  }

  Output("ECSInstanceProfile") {
    Value(Ref('InstanceProfile'))
  }

}
