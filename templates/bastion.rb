CloudFormation do

  # Template metadata
  AWSTemplateFormatVersion '2010-09-09'
  Description "ciinabox - Bastion v#{ciinabox_version}"

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
  Mapping('bastionAMI', bastionAMI)

  Resource('Role') {
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
            PolicyName: 'associate-address',
            PolicyDocument: {
                Statement: [
                    {
                        Effect: 'Allow',
                        Action: ['ec2:AssociateAddress'],
                        Resource: '*'
                    }
                ]
            }
        },
        {
            PolicyName: 'describe-ec2-autoscaling',
            PolicyDocument: {
                Statement: [
                    {
                        Effect:'Allow',
                        Action: ['ec2:Describe*', 'autoscaling:Describe*' ],
                        Resource: [ '*' ]
                    }
                ]
            }
        }
    ])
  }

  InstanceProfile('InstanceProfile') {
    Path '/'
    Roles [ Ref('Role') ]
  }

  Resource('BastionIPAddress') {
    Type 'AWS::EC2::EIP'
    Property('Domain', 'vpc')
  }

  Resource('LaunchConfig') {
    Type 'AWS::AutoScaling::LaunchConfiguration'
    DependsOn ['BastionIPAddress']
    Property('ImageId', FnFindInMap('bastionAMI', Ref('AWS::Region'), 'ami'))
    Property('KeyName', FnFindInMap('EnvironmentType', 'ciinabox', 'KeyName'))
    Property('AssociatePublicIpAddress',true)
    Property('IamInstanceProfile', Ref('InstanceProfile'))
    FnFindInMap('EnvironmentType', 'ciinabox', 'KeyName')
    Property('SecurityGroups', [ Ref('SecurityGroupDev'),
        Ref('SecurityGroupBackplane'),
        Ref('SecurityGroupOps') ])
    Property('InstanceType', bastionInstanceType)
    Property('UserData', FnBase64(FnJoin('',[
        "#!/bin/bash\n",
        'export NEW_HOSTNAME=', Ref('EnvironmentName'),"-bastion-xx-`/opt/aws/bin/ec2-metadata --instance-id|/usr/bin/awk '{print $2}'`", "\n",
        "echo \"NEW_HOSTNAME=$NEW_HOSTNAME\" \n",
        "hostname $NEW_HOSTNAME\n",
        "sed -i \"s/^HOSTNAME=.*/HOSTNAME=$NEW_HOSTNAME/\" /etc/sysconfig/network\n",
        'aws --region ', Ref('AWS::Region'), ' ec2 associate-address --allocation-id ', FnGetAtt('BastionIPAddress','AllocationId') ," --instance-id $(curl http://169.254.169.254/2014-11-05/meta-data/instance-id -s)\n",
    ])))
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
    addTag('Name', FnJoin('-',[Ref('EnvironmentName'), 'bastion' , 'xx']), true)
    addTag('Environment', Ref('EnvironmentName'), true)
    addTag('EnvironmentType', Ref('EnvironmentType'), true)
    addTag('Role', 'bastion', true)
  }

  Resource('BastionRecordSet') {
    Type 'AWS::Route53::RecordSet'
    DependsOn ['BastionIPAddress']
    Property('HostedZoneName', FnJoin('', [ dns_domain, '.' ]))
    Property('Comment', 'Bastion record set')
    Property('Name', FnJoin('', [ 'bastion.',  Ref('EnvironmentName') , '.', dns_domain, '.' ]))
    Property('Type', 'A')
    Property('TTL', '60')
    Property('ResourceRecords', [  Ref('BastionIPAddress') ] )
  }

end
