# ciinabox cfndsl helpers
def add_security_group_rules (access_list)
  rules = []
  access_list.each do |ip|
    rules << { IpProtocol: 'tcp', FromPort: '22', ToPort: '22', CidrIp: ip }
  end
end
