

# Prompts user for Yes/No answer on standard input
def prompt_yes_no(message)
  answer = nil
  while answer.nil?
    tmp_answer = get_input(message + ' (y/n)')
    if (tmp_answer.downcase == 'y' || tmp_answer == 'n')
      answer = tmp_answer == 'y'
    else
      puts "!!Please provide valid input (y/n)!!"
    end
  end
  return answer
end

# Execute AWS command via command line, collects output optionally
def aws_execute(config, cmd, output = nil)
  config['aws_profile'].nil? ? '' : cmd << "--profile #{config['aws_profile']}"
  config['aws_region'].nil? ? '' : cmd << "--region #{config['aws_region']}"
  args = cmd.join(" ")
  if config['log_level'] == :debug
    puts "executing: aws #{args}"
  end
  if output.nil?
    result = `aws #{args} 2>&1`
  else
    result = `aws #{args} > #{output}`
  end
  return $?.to_i, result
end

# Reads a line from STDIN
def get_input(prompt)
  puts prompt
  $stdin.gets.chomp
end