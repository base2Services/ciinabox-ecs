# ciinabox cfndsl helpers

def has_cac ()
  ciinaboxes_dir = ENV['CIINABOXES_DIR'] || 'ciinaboxes'
  ciinabox_name = ENV['CIINABOX'] || ''
  return File.exist?("#{ciinaboxes_dir}/#{ciinabox_name}/config/jenkins_configuration_as_code.yml")
end

def cac_yaml()
  ciinaboxes_dir = ENV['CIINABOXES_DIR'] || 'ciinaboxes'
  ciinabox_name = ENV['CIINABOX'] || ''
  return YAML.load(File.read("#{ciinaboxes_dir}/#{ciinabox_name}/config/jenkins_configuration_as_code.yml"))
end

def cac_tar_url(source_bucket, ciinabox_version)
  return "s3://#{source_bucket}/ciinabox/#{ciinabox_version}/configurationascode/overlay.tar"
end

