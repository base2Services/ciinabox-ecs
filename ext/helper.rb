# ciinabox cfndsl helpers
def add_security_group_rules (access_list)
  rules = []
  access_list.each do |ip|
    rules << { IpProtocol: 'tcp', FromPort: '22', ToPort: '22', CidrIp: ip }
  end
end

def nat_scale_up_schedule(scale_up_schedule)
  expr = scale_up_schedule.split
  hour = expr[1].to_i
  minute = expr[0].to_i
  if minute < 10
    minute = 60 + minute - 10
    hour = hour - 1
  else
    minute = minute - 10
  end
  return "#{minute} #{hour} #{expr[2]} #{expr[3]} #{expr[4]}"
end
