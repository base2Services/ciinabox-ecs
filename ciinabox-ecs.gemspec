require 'rake'
require 'date'

Gem::Specification.new do |s|
  s.name = 'ciinabox-ecs'
  s.version = '0.3.0'
  s.version = "#{s.version}.alpha.#{Time.now.getutc.to_i}" if ENV['TRAVIS'] and ENV['TRAVIS_BRANCH'] != 'master'
  s.date = Date.today.to_s
  s.summary = 'Manage ciinabox on Aws Ecs'
  s.description = ''
  s.authors = ['Base2Services']
  s.email = 'itsupport@base2services.com'
  s.files = FileList['lib/**/*.rb','ext/**/*', 'config/**/*', 'bin/**/*', 'lambdas/**/*', 'templates/**/*', 'Gemfile', 'Rakefile', 'README.md', 'LICENSE.txt']
  s.homepage = 'https://github.com/base2Services/ciinabox-ecs'
  s.license = 'MIT'
  s.executables << 'ciinabox-ecs'
  s.require_paths = ['lib']
  s.add_runtime_dependency 'rake', '~>12'
  s.add_runtime_dependency 'aws-sdk-s3', '~>1'
  s.add_runtime_dependency 'aws-sdk-cloudformation', '~>1'
  s.add_runtime_dependency 'cfndsl', '0.17.1'
  s.add_runtime_dependency 'cfn_manage', '~>0'
  s.add_runtime_dependency 'deep_merge', '~>1.2'
  s.add_runtime_dependency 'rubyzip', '~> 1.2'
end
