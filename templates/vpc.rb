require 'cfndsl'
require_relative '../ext/helper.rb'

CloudFormation {

  # Template metadata
  AWSTemplateFormatVersion "2010-09-09"
  Description "ciinabox - VPC v#{ciinabox_version}"

  # Global mappings
  Mapping('EnvironmentType', Mappings['EnvironmentType'])
  Mapping('NatAMI', natAMI)

  # Resources
  Resource("VPC") {
    Type 'AWS::EC2::VPC'
    Property('CidrBlock', FnJoin( "", [ FnFindInMap('EnvironmentType','ciinabox','NetworkPrefix'),".", FnFindInMap('EnvironmentType','ciinabox','StackOctet'), ".0.0/", FnFindInMap('EnvironmentType','ciinabox','StackMask') ] ))
    Property('EnableDnsSupport', true)
    Property('EnableDnsHostnames', true)
  }

  availability_zones.each do |az|

    Resource("SubnetPublic#{az}") {
      Type 'AWS::EC2::Subnet'
      Property('VpcId', Ref('VPC'))
      Property('CidrBlock', FnJoin( "", [ FnFindInMap('EnvironmentType','ciinabox','NetworkPrefix'), ".", FnFindInMap('EnvironmentType','ciinabox','StackOctet'), ".", vpc["SubnetOctet#{az}"], ".0/", FnFindInMap('EnvironmentType','ciinabox','SubnetMask') ] ))
      Property('AvailabilityZone', FnSelect(azId[az], FnGetAZs(Ref( "AWS::Region" )) ))
      Property('Tags',[
        {
          Key: 'Name', Value: FnJoin( "", [ "ciinabox-public#{az}"])
        }
      ])
    }
  end

  Resource("InternetGateway") {
    Type 'AWS::EC2::InternetGateway'
  }

  Resource("AttachGateway") {
    Type 'AWS::EC2::VPCGatewayAttachment'
    Property('VpcId', Ref('VPC'))
    Property('InternetGatewayId', Ref('InternetGateway'))
  }

  Resource("RouteTablePublic") {
    Type 'AWS::EC2::RouteTable'
    Property('VpcId', Ref('VPC'))
  }

  availability_zones.each do |az|
    Resource("RouteTablePrivate#{az}") {
      Type 'AWS::EC2::RouteTable'
      Property('VpcId', Ref('VPC'))
    }
  end

  availability_zones.each do |az|
    Resource("SubnetRouteTableAssociationPublic#{az}") {
      Type 'AWS::EC2::SubnetRouteTableAssociation'
      Property('SubnetId', Ref("SubnetPublic#{az}"))
      Property('RouteTableId', Ref('RouteTablePublic'))
    }
  end

  Resource("PublicRouteOutToInternet") {
    Type 'AWS::EC2::Route'
    Property('RouteTableId', Ref("RouteTablePublic"))
    Property('DestinationCidrBlock', '0.0.0.0/0')
    Property('GatewayId',Ref("InternetGateway"))
  }

  Resource("PublicNetworkAcl") {
    Type 'AWS::EC2::NetworkAcl'
    Property('VpcId', Ref('VPC'))
  }

  # Name => RuleNumber, Protocol, RuleAction, Egress, CidrBlock, PortRange From, PortRange To
  acls = {
    InboundHTTPPublicNetworkAclEntry:       ['100','6','allow','false','0.0.0.0/0','80','80'],
    InboundHTTPSPublicNetworkAclEntry:      ['101','6','allow','false','0.0.0.0/0','443','443'],
    InboundSSHPublicNetworkAclEntry:        ['102','6','allow','false','0.0.0.0/0','22','22'],
    InboundEphemeralPublicNetworkAclEntry:  ['103','6','allow','false','0.0.0.0/0','1024','65535'],
    OutboundNetworkAclEntry:                ['104','-1','allow','true','0.0.0.0/0','0','65535']
  }

  # merges acls defined in config with acls in vpc template incrementing the RuleNumber by 1
  if defined? customAcl
    rule_number = acls.length + 99
    customAcl.each do |acl|
      rule_number += 1
      acls.merge!((acl['Egress'] ? 'Outbound' : 'Inbound') + acl['Name'] + 'PublicNetworkAclEntry' =>
        [rule_number,acl['Protocol'],'allow',acl['Egress'],acl['CidrBlock'] ? acl['CidrBlock'] : '0.0.0.0/0',acl['Port'],acl['Port']])
    end
  end

  acls.each do |alcName,alcProperties|
    Resource(alcName) {
      Type 'AWS::EC2::NetworkAclEntry'
      Property('NetworkAclId', Ref('PublicNetworkAcl'))
      Property('RuleNumber', alcProperties[0])
      Property('Protocol', alcProperties[1])
      Property('RuleAction', alcProperties[2])
      Property('Egress', alcProperties[3])
      Property('CidrBlock', alcProperties[4])
      Property('PortRange',{
        From: alcProperties[5],
        To: alcProperties[6]
      })
    }
  end

  availability_zones.each do |az|
    Resource("SubnetNetworkAclAssociationPublic#{az}") {
      Type 'AWS::EC2::SubnetNetworkAclAssociation'
      Property('SubnetId', Ref("SubnetPublic#{az}"))
      Property('NetworkAclId', Ref('PublicNetworkAcl'))
    }
  end

  Resource("DHCPOptionSet") {
    Type 'AWS::EC2::DHCPOptions'
    Property('DomainName',  dns_domain)
    Property('DomainNameServers', ['AmazonProvidedDNS'])
  }

  Resource("DHCPOptionsAssociation") {
    Type 'AWS::EC2::VPCDHCPOptionsAssociation'
    Property('VpcId', Ref('VPC'))
    Property('DhcpOptionsId', Ref('DHCPOptionSet'))
  }

  rules = []
  opsAccess.each do |ip|
    rules << { IpProtocol: 'tcp', FromPort: '22', ToPort: '22', CidrIp: ip }
    rules << { IpProtocol: 'tcp', FromPort: '80', ToPort: '80', CidrIp: ip }
    rules << { IpProtocol: 'tcp', FromPort: '443', ToPort: '443', CidrIp: ip }
    rules << { IpProtocol: 'tcp', FromPort: '50000', ToPort: '50000', CidrIp: ip }
  end

  Resource("SecurityGroupOps") {
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', 'Ops External Access')
    Property('SecurityGroupIngress', rules)
  }

  rules = []
  devAccess.each do |ip|
    rules << { IpProtocol: 'tcp', FromPort: '22', ToPort: '22', CidrIp: ip }
    rules << { IpProtocol: 'tcp', FromPort: '80', ToPort: '80', CidrIp: ip }
    rules << { IpProtocol: 'tcp', FromPort: '443', ToPort: '443', CidrIp: ip }
    rules << { IpProtocol: 'tcp', FromPort: '50000', ToPort: '50000', CidrIp: ip }
  end

  Resource("SecurityGroupDev") {
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', 'Dev Team Access')
    Property('SecurityGroupIngress', rules)
  }

  Resource("SecurityGroupBackplane") {
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', 'Backplane SG')
    Property('SecurityGroupIngress', [
      { IpProtocol: 'tcp', FromPort: '22', ToPort: '22', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType','ciinabox','NetworkPrefix'),".", FnFindInMap('EnvironmentType','ciinabox','StackOctet'), ".0.0/",FnFindInMap('EnvironmentType','ciinabox','StackMask') ] ) },
      { IpProtocol: 'tcp', FromPort: '80', ToPort: '80', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType','ciinabox','NetworkPrefix'),".", FnFindInMap('EnvironmentType','ciinabox','StackOctet'), ".0.0/",FnFindInMap('EnvironmentType','ciinabox','StackMask') ] ) },
      { IpProtocol: 'tcp', FromPort: '443', ToPort: '443', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType','ciinabox','NetworkPrefix'),".", FnFindInMap('EnvironmentType','ciinabox','StackOctet'), ".0.0/",FnFindInMap('EnvironmentType','ciinabox','StackMask') ] ) },
      { IpProtocol: 'tcp', FromPort: '8080', ToPort: '8080', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType','ciinabox','NetworkPrefix'),".", FnFindInMap('EnvironmentType','ciinabox','StackOctet'), ".0.0/",FnFindInMap('EnvironmentType','ciinabox','StackMask') ] ) },
      { IpProtocol: 'tcp', FromPort: '50000', ToPort: '50000', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType','ciinabox','NetworkPrefix'),".", FnFindInMap('EnvironmentType','ciinabox','StackOctet'), ".0.0/",FnFindInMap('EnvironmentType','ciinabox','StackMask') ] ) },
      { IpProtocol: 'tcp', FromPort: '3389', ToPort: '3389', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType','ciinabox','NetworkPrefix'),".", FnFindInMap('EnvironmentType','ciinabox','StackOctet'), ".0.0/",FnFindInMap('EnvironmentType','ciinabox','StackMask') ] ) },
      { IpProtocol: 'tcp', FromPort: '5985', ToPort: '5985', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType','ciinabox','NetworkPrefix'),".", FnFindInMap('EnvironmentType','ciinabox','StackOctet'), ".0.0/",FnFindInMap('EnvironmentType','ciinabox','StackMask') ] ) },
    ])
  }

  Resource("SecurityGroupInternalNat") {
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', 'Internal NAT SG')
    Property('SecurityGroupIngress', [
      { IpProtocol: 'tcp', FromPort: '1', ToPort: '65535', CidrIp: FnJoin( "", [FnFindInMap('EnvironmentType','ciinabox','NetworkPrefix'),".", FnFindInMap('EnvironmentType','ciinabox','StackOctet'), ".0.0/", FnFindInMap('EnvironmentType','ciinabox','StackMask') ] ) }
    ])
  }

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
        PolicyName: 'AttachNetworkInterface',
        PolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Action: [ 'ec2:DescribeNetworkInterfaces', 'ec2:AttachNetworkInterface' ],
              Resource: '*'
            }
          ]
        }
      }
    ])
  }

  Resource("InstanceProfile") {
    Type 'AWS::IAM::InstanceProfile'
    Property('Path','/')
    Property('Roles',[ Ref('Role') ])
  }

  availability_zones.each do |az|
    Resource("NatIPAddress#{az}") {
      Type 'AWS::EC2::EIP'
      Property('Domain', 'vpc')
    }
  end

  availability_zones.each do |az|
    Resource("NetworkInterface#{az}") {
      Type 'AWS::EC2::NetworkInterface'
      Property('SubnetId', Ref("SubnetPublic#{az}"))
      Property('SourceDestCheck', false)
      Property('GroupSet', [
        Ref('SecurityGroupInternalNat'),
        Ref('SecurityGroupOps'),
        Ref('SecurityGroupBackplane'),
        Ref('SecurityGroupDev')
      ])
      Property('Tags',[
        {
          'Key' => 'reservation',
          'Value' => FnJoin("",[ 'ciinabox', "-nat-#{az.downcase}"])
        }
      ])
    }
  end

  availability_zones.each do |az|
    Resource("EIPAssociation#{az}") {
      Type 'AWS::EC2::EIPAssociation'
      Property('AllocationId', FnGetAtt("NatIPAddress#{az}",'AllocationId'))
      Property('NetworkInterfaceId', Ref("NetworkInterface#{az}"))
    }
  end

  availability_zones.each do |az|
    Resource("RouteOutToInternet#{az}") {
      Type 'AWS::EC2::Route'
      Property('RouteTableId', Ref("RouteTablePrivate#{az}"))
      Property('DestinationCidrBlock', '0.0.0.0/0')
      Property('NetworkInterfaceId',Ref("NetworkInterface#{az}"))
    }
  end
  availability_zones.each do |az|

    Resource("LaunchConfig#{az}") {
      Type 'AWS::AutoScaling::LaunchConfiguration'
      Property('ImageId', FnFindInMap('NatAMI',Ref('AWS::Region'),'ami') )
      Property('AssociatePublicIpAddress',true)
      Property('IamInstanceProfile', Ref('InstanceProfile'))
      Property('KeyName', FnFindInMap('EnvironmentType','ciinabox','KeyName') )
      Property('SecurityGroups',[ Ref('SecurityGroupBackplane'),Ref('SecurityGroupInternalNat'),Ref('SecurityGroupOps') ])
      Property('InstanceType', FnFindInMap('EnvironmentType','ciinabox','NatInstanceType'))
      Property('UserData', FnBase64(FnJoin("",[
        "#!/bin/bash\n",
        "export NEW_HOSTNAME=nat#{az}-ciinabox-`/opt/aws/bin/ec2-metadata --instance-id|/usr/bin/awk '{print $2}'`\n",
        "echo \"NEW_HOSTNAME=$NEW_HOSTNAME\" \n",
        "hostname $NEW_HOSTNAME\n",
        "sed -i \"s/^\(HOSTNAME=\).*/\\$NEW_HOSTNAME/\" /etc/sysconfig/network\n",
        "ATTACH_ID=`aws ec2 describe-network-interfaces --query 'NetworkInterfaces[*].[Attachment][*][*].AttachmentId' --filter Name=network-interface-id,Values='", Ref("NetworkInterface#{az}") ,"' --region ", Ref("AWS::Region"), " --output text`\n",
        "aws ec2 detach-network-interface --attachment-id $ATTACH_ID  --region", Ref("AWS::Region") ," --force \n",
        "aws ec2 attach-network-interface --instance-id $(curl http://169.254.169.254/2014-11-05/meta-data/instance-id -s) --network-interface-id ", Ref("NetworkInterface#{az}") ," --device-index 1 --region ", Ref("AWS::Region"), "\n",
        "sysctl -w net.ipv4.ip_forward=1\n",
        "iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE\n",
        "GW=$(curl -s http://169.254.169.254/2014-11-05/meta-data/local-ipv4/ | cut -d '.' -f 1-3).1\n",
        "route del -net 0.0.0.0 gw $GW netmask 0.0.0.0 dev eth0 metric 0\n",
        "route add -net 0.0.0.0 gw $GW netmask 0.0.0.0 dev eth0 metric 10002\n",
        "echo 'done!!!!'\n"
      ])))
    }

    AutoScalingGroup("AutoScaleGroup#{az}") {
      UpdatePolicy("AutoScalingRollingUpdate", {
        "MinInstancesInService" => "0",
        "MaxBatchSize"          => "1",
      })
      LaunchConfigurationName Ref("LaunchConfig#{az}")
      HealthCheckGracePeriod '500'
      MinSize 1
      MaxSize 1
      VPCZoneIdentifier [ Ref("SubnetPublic#{az}") ]
      addTag("Name", FnJoin("",["ciinabox-nat-#{az.downcase}"]), true)
      addTag("Environment",'ciinabox', true)
      addTag("EnvironmentType", 'ciinabox', true)
      addTag("Role", "nat", true)
    }

    if defined? scale_up_schedule
      Resource("ScheduledActionUp#{az}") {
        Type 'AWS::AutoScaling::ScheduledAction'
        Property('AutoScalingGroupName', Ref("AutoScaleGroup#{az}"))
        Property('MinSize','1')
        Property('MaxSize', '1')
        Property('DesiredCapacity', '1')
        Property('Recurrence', nat_scale_up_schedule(scale_up_schedule))
      }
    end

    if defined? scale_down_schedule
      Resource("ScheduledActionDown#{az}") {
        Type 'AWS::AutoScaling::ScheduledAction'
        Property('AutoScalingGroupName', Ref("AutoScaleGroup#{az}"))
        Property('MinSize','0')
        Property('MaxSize', '0')
        Property('DesiredCapacity', '0')
        Property('Recurrence', scale_down_schedule)
      }
    end

  end

  availability_zones.each do |az|
    Resource("Nat#{az}RecordSet") {
      Type 'AWS::Route53::RecordSet'
      DependsOn ["NetworkInterface#{az}"]
      Property('HostedZoneName', FnJoin('', [ dns_domain, '.' ]))
      Property('Comment', "ciinabox NAT Public Record Set")
      Property('Name', FnJoin('.', [ "nat#{az}",dns_domain ]))
      Property('Type', "A")
      Property('TTL', "60")
      Property('ResourceRecords', [ Ref("NatIPAddress#{az}") ] )
    }
  end

  route_tables = []
  availability_zones.each do |az|
    route_tables << Ref("RouteTablePrivate#{az}")
  end

  Resource("S3VPCEndpoint") {
    Type "AWS::EC2::VPCEndpoint"
    Property("PolicyDocument", {
      Version:"2012-10-17",
      Statement:[{
        Effect:"Allow",
        Principal: "*",
        Action:["*"],
        Resource:["arn:aws:s3:::*"]
      }]
    })
    Property("RouteTableIds", route_tables)
    Property("ServiceName", FnJoin("", [ "com.amazonaws.", Ref("AWS::Region"), ".s3"]))
    Property("VpcId",  Ref('VPC'))
  }


  Output("VPCId") {
    Value(Ref('VPC'))
  }

  availability_zones.each do |az|
    Output("RouteTablePrivate#{az}") {
      Value(Ref("RouteTablePrivate#{az}"))
    }
  end

  availability_zones.each do |az|
    Output("SubnetPublic#{az}") {
      Value(Ref("SubnetPublic#{az}"))
    }
  end

  Output("SecurityGroupBackplane") {
    Value(Ref('SecurityGroupBackplane'))
  }

  Output("SecurityGroupOps") {
    Value(Ref('SecurityGroupOps'))
  }

  Output("SecurityGroupDev") {
    Value(Ref('SecurityGroupDev'))
  }

}
