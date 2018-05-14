require 'rake'

Gem::Specification.new do |s|
  s.name = 'ciinabox-ecs'
  s.version = '0.2.8'
  s.date = '2018-05-07'
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
  s.add_runtime_dependency 'cfndsl', '~>0.15.2'
  s.add_runtime_dependency 'cfn_manage', '~>0.3.0'
  s.add_runtime_dependency 'deep_merge', '~>1.2'
  s.add_runtime_dependency 'rubyzip', '~> 1.2'
end
