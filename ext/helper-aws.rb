


# Sets ruby AWS SDK client to use named profile
def load_awssdk_credentials(aws_profile)
  if not aws_profile.nil?
    Aws.config[:credentials] = Aws::SharedCredentials.new(profile_name: aws_profile)
  end
end