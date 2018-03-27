require 'yaml'

module Configs
  class << self; attr_accessor :managed_policies, :all end
  @managed_policies = YAML.load(File.read('ext/config/managed_policies.yml'))
  @all = Hash.new.tap { |h| Dir['config/*.yml'].each { |yml| h.merge!(YAML.load(File.open(yml))) }}
  # Override with ciinabox configs
  ciinaboxes_dir = ENV['CIINABOXES_DIR'] || 'ciinaboxes'
  ciinabox_name = ENV['CIINABOX'] || ''
  (Dir["#{ciinaboxes_dir}/#{ciinabox_name}/config/*.yml"]).each { |yml|
      @all.merge!(YAML.load(File.open(yml)))
  }
end

class Policies

  def initialize
    @policy_array = Array.new
    @config = Configs.all
    @policies = (@config.key?('custom_policies') ? Configs.managed_policies.merge(@config['custom_policies']) : Configs.managed_policies)
  end

  def get_policies(group = nil)
    create_policies(@config['default_policies']) if @config.key?('default_policies')
    create_policies(@config['group_policies'][group]) unless group.nil?
    return @policy_array
  end

  def create_policies(policies)
    policies.each do |policy|
      raise "ERROR: #{policy} policy doesn't exist in the managed policies or as a custom policy" unless @policies.key?(policy)
      resource = (@policies[policy].key?('resource') ? gsub_yml(@policies[policy]['resource']) : ["*"])
      @policy_array << { PolicyName: policy, PolicyDocument: { Statement: [ { Effect:"Allow", Action: @policies[policy]['action'], Resource: resource }]} }
    end
    return @policy_array
  end

  # replaces %{variables} in the yml
  def gsub_yml(resource)
    replaced = []
    resource.each { |r|
      if r.is_a? String
        replaced << r.gsub('%{source_bucket}', @config['source_bucket'])
      else
        replaced << r
      end
    }

    return replaced
  end

end
