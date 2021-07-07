#!/usr/bin/env ruby

require 'rake'
require 'optparse'

class CiinaboxEcsCli

  def main(args)
    script_dir = File.expand_path File.dirname(__FILE__)
    old_pwd = Dir.pwd

    Rake::TaskManager.record_task_metadata = true

    Dir.chdir script_dir
    app = Rake.application
    app.init
    app.load_rakefile

    actions = app.tasks.map { |t| t.name.gsub('ciinabox:', '') }

    required_args_size = ENV.key?('CIINABOX') ? 1 : 2

    if (args.size() ==0) or
        (args.size() < required_args_size and (not %w(init full_install).include? args[0])) or
        (args[0] == 'help') or
        (not actions.include? args[0])
      STDERR.puts("Usage: ciinabox-ecs action1 action2 action3 ciinabox_name")
      STDERR.puts("Valid actions:")
      STDERR.printf("%-20s |%-20s\n\n", 'name', 'description')
      app.tasks.each do |action|
        STDERR.printf("%-20s |%-20s\n", action.name.gsub('ciinabox:', ''), action.comment)
      end
      exit 0 if args[0] == 'help'
      exit -1
    end

    margs = args.select{|i| !(i =~ /^-/)}
    methods = margs[0..margs.size()-2]

    unless ENV.key? 'CIINABOX'
      ciinabox_name = margs[margs.size()-1]
      ENV['CIINABOX'] = ciinabox_name
    end

    if ENV.key? 'CIINABOXES_DIR'
      ENV['CIINABOXES_DIR'] = File.expand_path(ENV['CIINABOXES_DIR'])
    else
      ENV['CIINABOXES_DIR'] = old_pwd
    end

    methods.each do |method_name|
      Dir.chdir(script_dir)
      Rake.application = nil
      app = Rake.application
      app.init
      app.load_rakefile
      Dir.chdir(old_pwd)
      app["ciinabox:#{method_name}"].invoke()
    end

  end

end

CiinaboxEcsCli.new.main(ARGV)
