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
    Property('Tags',[ {Key: 'Name', Value: stack_name }])
  }

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

  Resource("NatGatewayEIP") {
    Type 'AWS::EC2::EIP'
    Property('Domain', 'vpc')
  }

  Resource("NatGateway") {
    DependsOn 'AttachGateway'
    Type 'AWS::EC2::NatGateway'
    Property('AllocationId', FnGetAtt("NatGatewayEIP",'AllocationId'))
    Property('SubnetId', Ref("SubnetPublic#{availability_zones[0]}"))
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

  availability_zones.each do |az|
    Resource("RouteOutToInternet#{az}") {
      Type 'AWS::EC2::Route'
      Property('RouteTableId', Ref("RouteTablePrivate#{az}"))
      Property('DestinationCidrBlock', '0.0.0.0/0')
      Property('NatGatewayId',Ref("NatGateway"))
    }
  end

  Resource("PublicNetworkAcl") {
    Type 'AWS::EC2::NetworkAcl'
    Property('VpcId', Ref('VPC'))
  }

  # Name => RuleNumber, Protocol, RuleAction, Egress, CidrBlock, PortRange From, PortRange To
  acls = {
    # Inbound
    InboundTCPEphemeralPublicNetworkAclEntry: ['1001','6','allow','false','0.0.0.0/0','1024','65535'],
    InboundUDPEphemeralPublicNetworkAclEntry: ['1002','17','allow','false','0.0.0.0/0','1024','65535'],
    InboundSSHPublicNetworkAclEntry:          ['1003','6','allow','false','0.0.0.0/0','22','22'],
    InboundHTTPPublicNetworkAclEntry:         ['1004','6','allow','false','0.0.0.0/0','80','80'],
    InboundHTTPSPublicNetworkAclEntry:        ['1005','6','allow','false','0.0.0.0/0','443','443'],
    InboundNTPPublicNetworkAclEntry:          ['1006','17','allow','false','0.0.0.0/0','123','123'],
    InboundRDPPublicNetworkAclEntry:          ['1007','6','allow','false','0.0.0.0/0','3389','3389'],

    # Outbound
    OutboundNetworkAclEntry:                  ['1001','-1','allow','true','0.0.0.0/0','0','65535']
  }

  # merges acls defined in config with acls in vpc template incrementing the RuleNumber by 1
  if defined? customAcl
    rule_number = 2000
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

  rules = []
  opsAccess.each do |ip|
    rules << { IpProtocol: 'tcp', FromPort: '22', ToPort: '22', CidrIp: ip }
    rules << { IpProtocol: 'tcp', FromPort: '80', ToPort: '80', CidrIp: ip }
    rules << { IpProtocol: 'tcp', FromPort: '443', ToPort: '443', CidrIp: ip }
    rules << { IpProtocol: 'tcp', FromPort: '3389', ToPort: '3389', CidrIp: ip }
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
    rules << { IpProtocol: 'tcp', FromPort: '3389', ToPort: '3389', CidrIp: ip }
    rules << { IpProtocol: 'tcp', FromPort: '50000', ToPort: '50000', CidrIp: ip }
  end

  Resource("SecurityGroupDev") {
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', 'Dev Team Access')
    Property('SecurityGroupIngress', rules)
  }


  nat_allow_sg_ingress = [
      {IpProtocol: 'tcp', FromPort: '22', ToPort: '22', CidrIp: FnJoin('', [Ref('NatGatewayEIP'), '/32'])},
      {IpProtocol: 'tcp', FromPort: '80', ToPort: '80', CidrIp: FnJoin('', [Ref('NatGatewayEIP'), '/32'])},
      {IpProtocol: 'tcp', FromPort: '443', ToPort: '443', CidrIp: FnJoin('', [Ref('NatGatewayEIP'), '/32'])},
      {IpProtocol: 'tcp', FromPort: '8080', ToPort: '8080', CidrIp: FnJoin('', [Ref('NatGatewayEIP'), '/32'])},
      {IpProtocol: 'tcp', FromPort: '50000', ToPort: '50000', CidrIp: FnJoin('', [Ref('NatGatewayEIP'), '/32'])},
      {IpProtocol: 'tcp', FromPort: '3389', ToPort: '3389', CidrIp: FnJoin('', [Ref('NatGatewayEIP'), '/32'])},
      {IpProtocol: 'tcp', FromPort: '5666', ToPort: '5666', CidrIp: FnJoin('', [Ref('NatGatewayEIP'), '/32'])},
      {IpProtocol: 'tcp', FromPort: '5985', ToPort: '5985', CidrIp: FnJoin('', [Ref('NatGatewayEIP'), '/32'])},
  ]

  allow_sg_ingress = [
      { IpProtocol: 'tcp', FromPort: '22', ToPort: '22', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType','ciinabox','NetworkPrefix'),".", FnFindInMap('EnvironmentType','ciinabox','StackOctet'), ".0.0/",FnFindInMap('EnvironmentType','ciinabox','StackMask') ] ) },
      { IpProtocol: 'tcp', FromPort: '80', ToPort: '80', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType','ciinabox','NetworkPrefix'),".", FnFindInMap('EnvironmentType','ciinabox','StackOctet'), ".0.0/",FnFindInMap('EnvironmentType','ciinabox','StackMask') ] ) },
      { IpProtocol: 'tcp', FromPort: '443', ToPort: '443', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType','ciinabox','NetworkPrefix'),".", FnFindInMap('EnvironmentType','ciinabox','StackOctet'), ".0.0/",FnFindInMap('EnvironmentType','ciinabox','StackMask') ] ) },
      { IpProtocol: 'tcp', FromPort: '8080', ToPort: '8080', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType','ciinabox','NetworkPrefix'),".", FnFindInMap('EnvironmentType','ciinabox','StackOctet'), ".0.0/",FnFindInMap('EnvironmentType','ciinabox','StackMask') ] ) },
      { IpProtocol: 'tcp', FromPort: '50000', ToPort: '50000', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType','ciinabox','NetworkPrefix'),".", FnFindInMap('EnvironmentType','ciinabox','StackOctet'), ".0.0/",FnFindInMap('EnvironmentType','ciinabox','StackMask') ] ) },
      { IpProtocol: 'tcp', FromPort: '3389', ToPort: '3389', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType','ciinabox','NetworkPrefix'),".", FnFindInMap('EnvironmentType','ciinabox','StackOctet'), ".0.0/",FnFindInMap('EnvironmentType','ciinabox','StackMask') ] ) },
      { IpProtocol: 'tcp', FromPort: '5666', ToPort: '5666', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType','ciinabox','NetworkPrefix'),".", FnFindInMap('EnvironmentType','ciinabox','StackOctet'), ".0.0/",FnFindInMap('EnvironmentType','ciinabox','StackMask') ] ) },
      { IpProtocol: 'tcp', FromPort: '5985', ToPort: '5985', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType','ciinabox','NetworkPrefix'),".", FnFindInMap('EnvironmentType','ciinabox','StackOctet'), ".0.0/",FnFindInMap('EnvironmentType','ciinabox','StackMask') ] ) },
  ]

  Resource('SecurityGroupNatGateway'){
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', 'Nat Gateway SG')
    Property('SecurityGroupIngress', nat_allow_sg_ingress)
  }

  Resource("SecurityGroupBackplane") {
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', 'Backplane SG')
    Property('SecurityGroupIngress', allow_sg_ingress)
  }

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

  Output('SecurityGroupNatGateway') {
    Value(Ref('SecurityGroupNatGateway'))
  }

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
