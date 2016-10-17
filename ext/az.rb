$maximum_availability_zones = 5
$subnet_multiplier = 8

def az_condtions (x=$maximum_availability_zones)
  x.times do |az|
    Condition("Az#{az}", FnNot([FnEquals(FnFindInMap(Ref("AWS::AccountId"),Ref("AWS::Region"),az),false)]))
  end
end

def az_count (x=$maximum_availability_zones)
  x.times do |i|
    tf = []
    (i+1).times do |y|
      tf << {"Condition" => "Az#{y}"}
    end
    (x-(i+1)).times do |z|
      tf << FnNot(["Condition" => "Az#{i+z+1}"])
    end
    Condition("#{i+1}Az", FnAnd(tf))
  end
end

def az_conditional_resources (resource_name,x=$maximum_availability_zones)
  if x.to_i > 0
    resources = []
    x.times do |y|
      resources << Ref("#{resource_name}#{y}")
    end
    if_statement = FnIf("#{x}Az",resources,az_conditional_resources(resource_name,x-1))
    return if_statement
  else
    return Ref("#{resource_name}#{x}")
  end
end

def az_create_subnets (subnet_allocation,subnet_name,vpc='VPC',x=$maximum_availability_zones,subnet_multiplier=$subnet_multiplier)
  x.times do |az|
    Resource("#{subnet_name}#{az}") {
      Condition "Az#{az}"
      Type 'AWS::EC2::Subnet'
      Property('VpcId', Ref("#{vpc}"))
      Property('CidrBlock', FnJoin( "", ['10.', Ref('StackOctet'), ".#{subnet_allocation * subnet_multiplier + az}.0/24"]))
      Property('AvailabilityZone', FnFindInMap(Ref("AWS::AccountId"),Ref("AWS::Region"),az))
    }
  end
end
