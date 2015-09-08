require 'cfndsl'

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
                'ecs:CreateCluster',
                'ecs:DeregisterContainerInstance',
                'ecs:DiscoverPollEndpoint',
                'ecs:Poll',
                'ecs:RegisterContainerInstance',
                'ecs:Submit*',
                'elasticloadbalancing:Describe*',
                'elasticloadbalancing:DeregisterInstancesFromLoadBalancer',
                'elasticloadbalancing:RegisterInstancesWithLoadBalancer',
                'ec2:Describe*',
                'ec2:AuthorizeSecurityGroupIngress'
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
                'ec2:ModifyImageAttribute'
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

  Volume("ECSDataVolume") {
    DeletionPolicy 'Snapshot'
    Size '100'
    VolumeType 'gp2'
    AvailabilityZone FnSelect(0, FnGetAZs(""))
    addTag("Name", "ciinabox-ecs-data-xx")
    addTag("Environment", 'ciinabox')
    addTag("EnvironmentType", 'ciinabox')
    addTag("Role", "search")
  }

  LaunchConfiguration( :LaunchConfig ) {
    ImageId FnFindInMap('ecsAMI',Ref('AWS::Region'),'ami')
    IamInstanceProfile Ref('InstanceProfile')
    KeyName FnFindInMap('EnvironmentType','ciinabox','KeyName')
    SecurityGroups [ Ref('SecurityGroupBackplane') ]
    InstanceType FnFindInMap('EnvironmentType','ciinabox','ECSInstanceType')
    UserData FnBase64(FnJoin("",[
      "#!/bin/bash\n",
      "echo ECS_CLUSTER=", Ref('ECSCluster'), " >> /etc/ecs/ecs.config\n",
      "INSTANCE_ID=`/opt/aws/bin/ec2-metadata -i | cut -f2 -d: | cut -f2 -d-`\n",
      "PRIVATE_IP=`/opt/aws/bin/ec2-metadata -o | cut -f2 -d: | cut -f2 -d-`\n",
      "yum install -y python-pip\n",
      "python-pip install --upgrade awscli\n",
      "/usr/local/bin/aws --region ", Ref("AWS::Region"), " ec2 attach-volume --volume-id ", Ref('ECSDataVolume'), " --instance-id i-${INSTANCE_ID} --device /dev/sdf\n",
      "[[ `file -s /dev/xvdf` == \"/dev/xvdf: data\" ]] && mkfs -t ext4 /dev/xvdf\n",
      "mkdir -p /data\n",
      "echo '/dev/xvdf   /data        ext4    defaults,nofail 0   2' >> /etc/fstab\n",
      "mount -a\n",
      "chmod -R 777 /data\n",
      "stop ecs\n",
      "service docker restart\n",
      "start ecs\n",
      "docker run --name jenkins-docker-slave --privileged=true -d -e PORT=4444 -p 4444:4444 -p 2223:22 -v /data/dind/:/var/lib/docker base2/ciinabox-jenkins-slave start-dind\n",
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

}
