require 'cfndsl'

userdata = {}

userdata['linux'] = [
  "!#/bin/bash\n",
]

userdata['windows'] = [
  "<powershell>\n",
  "</powershell>\n"
]

CloudFormation {

  # Template metadata
  AWSTemplateFormatVersion "2010-09-09"
  Description "ciinabox - Jenkins EC2 Slaves v#{ciinabox_version}"

  # Parameters
  Parameter("ECSCluster") {Type 'String'}
  Parameter("VPC") {Type 'String'}
  Parameter("RouteTablePrivateA") {Type 'String'}
  Parameter("RouteTablePrivateB") {Type 'String'}
  Parameter("SubnetPublicA") {Type 'String'}
  Parameter("SubnetPublicB") {Type 'String'}
  Parameter("SecurityGroupBackplane") {Type 'String'}
  Parameter('SecurityGroupNatGateway') {Type 'String'}

  Mapping('EnvironmentType', Mappings['EnvironmentType'])
  Mapping('windowsSlaveAMI', windows_jenkins_slave_ami) if include_windows_spot_slave
  Mapping('linuxSlaveAMI', linux_jenkins_slave_ami) if include_linux_spot_slave

  availability_zones.each do |az|
    Resource("SubnetPrivate#{az}") {
      Type 'AWS::EC2::Subnet'
      Property('VpcId', Ref('VPC'))
      Property('CidrBlock', FnJoin("", [FnFindInMap('EnvironmentType', 'ciinabox', 'NetworkPrefix'), ".", FnFindInMap('EnvironmentType', 'ciinabox', 'StackOctet'), ".", jenkinsSlaves["SubnetOctet#{az}"], ".0/", FnFindInMap('EnvironmentType', 'ciinabox', 'SubnetMask')]))
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

  Resource("Role") {
    Type 'AWS::IAM::Role'
    Property('AssumeRolePolicyDocument', {
      Statement: [
        Effect: 'Allow',
        Principal: { Service: [ 'ec2.amazonaws.com' ] },
        Action: [ 'sts:AssumeRole' ]
      ]
    })
    Property('Path', '/')
    Property('Policies', Policies.new.get_policies())
  }

  Resource("InstanceProfile") {
    Type 'AWS::IAM::InstanceProfile'
    Property('Path', '/')
    Property('Roles', [ Ref('Role') ])
  }

  policies = []
  policies << {
    PolicyName: 'spotRole',
    PolicyDocument:
    {
      Statement:
      [
        {
          Effect: 'Allow',
          Action:
          [
            'ec2:DescribeImages',
            'ec2:DescribeSubnets',
            'ec2:RequestSpotInstances',
            'ec2:TerminateInstances',
            'ec2:DescribeInstanceStatus',
            'iam:PassRole'
          ],
          Resource: ['*']
        }
      ]
    }
  }

  Resource('SpotIamRole') do
    Type 'AWS::IAM::Role'
    Property(
      'AssumeRolePolicyDocument',
      Statement: [
        Effect: 'Allow',
        Principal: { Service: ['spotfleet.amazonaws.com'] },
        Action: ['sts:AssumeRole']
      ]
    )
    Property('Path', '/')
    Property('Policies', policies)
  end

  ['windows','linux'].each do |slave,params|

    next if slave == 'windows' and !include_windows_spot_slave
    next if slave == 'linux' and !include_linux_spot_slave

    abort("ERROR: No spot pricing in config") if !defined? spot_launch_specifications

    launchSpecifications = []
    availability_zones.each do |az|
      spot_launch_specifications.each do | ls |
        launchSpecifications << {
          ImageId: FnFindInMap("#{slave}SlaveAMI", Ref('AWS::Region'), 'ami'),
          InstanceType: ls['InstanceType'],
          KeyName: FnFindInMap('EnvironmentType', 'ciinabox', 'KeyName'),
          WeightedCapacity: ls['WeightedCapacity'],
          SpotPrice: ls['SpotPrice'],
          IamInstanceProfile: { Arn: FnGetAtt('InstanceProfile','Arn') },
          SecurityGroups: [ { GroupId: Ref('SecurityGroupBackplane') } ],
          SubnetId: Ref("SubnetPrivate#{az}"),
          UserData: FnBase64(FnJoin('', userdata[slave]))
        }
      end
    end

    EC2_SpotFleet("#{slave}SpotFleet") do
      SpotFleetRequestConfigData ({
        IamFleetRole: FnGetAtt('SpotIamRole','Arn'),
        AllocationStrategy: "lowestPrice",
        SpotPrice: "0.2545",
        TargetCapacity: 1,
        LaunchSpecifications: launchSpecifications
      })
    end

end

}
