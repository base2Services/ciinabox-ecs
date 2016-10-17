require 'cfndsl'
require_relative '../ext/az'

CloudFormation do

  # Template metadata
  AWSTemplateFormatVersion "2010-09-09"
  Description "ciinabox - VPC v#{cf_version}"

  # Parameters
  Parameter("EnvironmentType"){ Type 'String' }
  Parameter("EnvironmentName"){ Type 'String' }
  Parameter("CostCenter"){ Type 'String' }
  Parameter("StackOctet") {
    Type 'String'
    AllowedPattern '[0-9]*'
  }
  $maximum_availability_zones.times do |az|
    Parameter("Nat#{az}EIPAllocationId") {
      Type 'String'
      Default 'dynamic'
    }
  end

  # Pre-rendered mappings
  mapped_availability_zones.each do |account,map|
    Mapping(account,map)
  end

  # Global mappings
  Mapping('EnvironmentType', EnvironmentType)
  Mapping('AccountId', AccountId)

  # Conditions
  az_condtions()
  az_count()

  maximum_availability_zones.times do |az|
    Condition("Nat#{az}EIPRequired", FnAnd([FnEquals(Ref("Nat#{az}EIPAllocationId"), 'dynamic'),"Condition" => "Az#{az}"]))
  end

  # Resources

  Resource("VPC") {
    Type 'AWS::EC2::VPC'
    Property('CidrBlock', FnJoin( '', [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'),".", Ref('StackOctet'), ".0.0/", FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'StackMask') ] ))
    Property('EnableDnsSupport', true)
    Property('EnableDnsHostnames', true)
  }

  Resource("HostedZone") {
    Type 'AWS::Route53::HostedZone'
    Property('Name', FnJoin('.', [ Ref('EnvironmentName'), FnFindInMap('AccountId', Ref('AWS::AccountId'),'DnsDomain') ]) )
  }

  Resource("DHCPOptionSet") {
    Type 'AWS::EC2::DHCPOptions'
    Property('DomainName', FnJoin('.', [ Ref('EnvironmentName'), FnFindInMap('AccountId',Ref('AWS::AccountId'),'DnsDomain') ]))
    Property('DomainNameServers', ['AmazonProvidedDNS'])
  }

  Resource("DHCPOptionsAssociation") {
    Type 'AWS::EC2::VPCDHCPOptionsAssociation'
    Property('VpcId', Ref('VPC'))
    Property('DhcpOptionsId', Ref('DHCPOptionSet'))
  }

  Resource("InternetGateway") {
    Type 'AWS::EC2::InternetGateway'
  }

  Resource("AttachGateway") {
    DependsOn ["InternetGateway"]
    Type 'AWS::EC2::VPCGatewayAttachment'
    Property('VpcId', Ref('VPC'))
    Property('InternetGatewayId', Ref('InternetGateway'))
  }

  az_create_subnets(stacks['vpc']['subnet_allocation'],'SubnetPublic')

  Resource("PublicNetworkAcl") {
    Type 'AWS::EC2::NetworkAcl'
    Property('VpcId', Ref('VPC'))
  }

  # Name: [ RuleNumber, Protocol, RuleAction, Egress, CidrBlock, PortRange From, PortRange To ]
  acls = {
      # Inbound rules
      InboundEphemeralPublicNetworkAclEntry:  ['100','6','allow','false','0.0.0.0/0','1024','65535'],
      InboundSSHPublicNetworkAclEntry:        ['101','6','allow','false','0.0.0.0/0','22','22'],
      InboundHTTPPublicNetworkAclEntry:       ['102','6','allow','false','0.0.0.0/0','80','80'],
      InboundHTTPSPublicNetworkAclEntry:      ['103','6','allow','false','0.0.0.0/0','443','443'],
      InboundNTPPublicNetworkAclEntry:        ['104','17','allow','false','0.0.0.0/0','123','123'],
      # Outbound rules
      OutboundNetworkAclEntry:                ['100','-1','allow','true','0.0.0.0/0','0','65535']
  }
  acls.each do |alcName,alcProperties|
    Resource(alcName) {
      Type 'AWS::EC2::NetworkAclEntry'
      Property('NetworkAclId', Ref('PublicNetworkAcl'))
      Property('RuleNumber', alcProperties[0])
      Property('Protocol', alcProperties[1])
      Property('RuleAction', alcProperties[2])
      Property('Egress', alcProperties[3])
      Property('CidrBlock', alcProperties[4])
      Property('PortRange',{ From: alcProperties[5], To: alcProperties[6] })
    }
  end

  maximum_availability_zones.times do |az|
    Resource("SubnetNetworkAclAssociationPublic#{az}") {
      Condition "Az#{az}"
      Type 'AWS::EC2::SubnetNetworkAclAssociation'
      Property('SubnetId', Ref("SubnetPublic#{az}"))
      Property('NetworkAclId', Ref('PublicNetworkAcl'))
    }
  end

  Resource("RouteTablePublic") {
    Type 'AWS::EC2::RouteTable'
    Property('VpcId', Ref('VPC'))
    Property('Tags',[ { Key: 'Name', Value: FnJoin( "", [ Ref('EnvironmentName'), "-public" ]) }])
  }

  maximum_availability_zones.times do |az|
    Resource("RouteTablePrivate#{az}") {
      Condition "Az#{az}"
      Type 'AWS::EC2::RouteTable'
      Property('VpcId', Ref('VPC'))
      Property('Tags',[ { Key: 'Name', Value: FnJoin("", [ Ref('EnvironmentName'), "-private#{az}" ]) } ])
    }
  end

  maximum_availability_zones.times do |az|
    Resource("SubnetRouteTableAssociationPublic#{az}") {
      Condition "Az#{az}"
      Type 'AWS::EC2::SubnetRouteTableAssociation'
      Property('SubnetId', Ref("SubnetPublic#{az}"))
      Property('RouteTableId', Ref('RouteTablePublic'))
    }
  end

  Resource("PublicRouteOutToInternet") {
    Type 'AWS::EC2::Route'
    DependsOn ["AttachGateway"]
    Property('RouteTableId', Ref("RouteTablePublic"))
    Property('DestinationCidrBlock', '0.0.0.0/0')
    Property('GatewayId',Ref("InternetGateway"))
  }

  maximum_availability_zones.times do |az|
    Resource("RouteOutToInternet#{az}") {
      Condition "Az#{az}"
      DependsOn ["NatGateway#{az}"]
      Type 'AWS::EC2::Route'
      Property('RouteTableId', Ref("RouteTablePrivate#{az}"))
      Property('DestinationCidrBlock', '0.0.0.0/0')
      Property('NatGatewayId',Ref("NatGateway#{az}"))
    }
  end

  maximum_availability_zones.times do |az|
    Resource("NatIPAddress#{az}") {
      DependsOn ["AttachGateway"]
      Condition("Nat#{az}EIPRequired")
      Type 'AWS::EC2::EIP'
      Property('Domain', 'vpc')
    }
  end

  maximum_availability_zones.times do |az|
    Resource("NatGateway#{az}") {
      Condition("Az#{az}")
      Type 'AWS::EC2::NatGateway'
      Property('AllocationId', FnIf("Nat#{az}EIPRequired",
                                    FnGetAtt("NatIPAddress#{az}",'AllocationId'),
                                    Ref("Nat#{az}EIPAllocationId")
      ))
      Property('SubnetId', Ref("SubnetPublic#{az}"))
    }
  end

  route_tables = az_conditional_resources('RouteTablePrivate')

  Resource("VPCEndpoint") {
    Type "AWS::EC2::VPCEndpoint"
    Property("PolicyDocument", {
        Version:"2012-10-17",
        Statement:[{
                       Effect:"Allow",
                       Principal: "*",
                       Action:["s3:*"],
                       Resource:["arn:aws:s3:::*"]
                   }]
    })
    Property("RouteTableIds", route_tables)
    Property("ServiceName", FnJoin("", [ "com.amazonaws.", Ref("AWS::Region"), ".s3"]))
    Property("VpcId",  Ref('VPC'))
  }

  opsRules = []
  opsAccess['ips'].each do |ip|
    opsAccess['rules'].each do |rules|
      opsRules << { IpProtocol: "#{rules['IpProtocol']}", FromPort: "#{rules['FromPort']}", ToPort: "#{rules['ToPort']}", CidrIp: ip }
    end
  end

  Resource("SecurityGroupOps") {
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', 'Ops External Access')
    Property('SecurityGroupIngress', opsRules)
  }

  devRules = []
  devAccess['ips'].each do |ip|
    devAccess['rules'].each do |rules|
      devRules << { IpProtocol: "#{rules['IpProtocol']}", FromPort: "#{rules['FromPort']}", ToPort: "#{rules['ToPort']}", CidrIp: ip }
    end
  end

  Resource("SecurityGroupDev") {
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', 'Dev Team Access')
    Property('SecurityGroupIngress', devRules)
  }

  #Backplane security group
  backplaneRules = []
  backplaneAccess['rules'].each do |rules|
    backplaneRules << { IpProtocol: "#{rules['IpProtocol']}", FromPort: "#{rules['FromPort']}", ToPort: "#{rules['ToPort']}", CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'), ".", Ref('StackOctet'), ".", "0.0/16" ] ) }
  end

  monitoringAccess['rules'].each do |rules|
    backplaneRules << { IpProtocol: "#{rules['IpProtocol']}", FromPort: "#{rules['FromPort']}", ToPort: "#{rules['ToPort']}", CidrIp: monitoringSubnet }
  end

  Resource("SecurityGroupBackplane") {
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', 'Backplane SG')
    Property('SecurityGroupIngress', backplaneRules)
  }

  # Outputs
  Output("VPCId") { Value(Ref('VPC')) }
  Output("SecurityGroupOps") { Value(Ref('SecurityGroupOps')) }
  Output("SecurityGroupDev") { Value(Ref('SecurityGroupDev')) }
  Output("SecurityGroupBackplane") { Value(Ref('SecurityGroupBackplane')) }
  maximum_availability_zones.times do |az|
    Output("RouteTablePrivate#{az}") { Value(FnIf("Az#{az}",Ref("RouteTablePrivate#{az}"),'')) }
    Output("SubnetPublic#{az}") { Value(FnIf("Az#{az}",Ref("SubnetPublic#{az}"),'')) }
  end
end
