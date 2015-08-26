#!/usr/bin/env ruby

require 'yaml'
require 'json'

# Prerequisities
#
# 1. There's a DNS A record pointing *.staging.yniche.com to the staging cluster.
#
# Workflow
#
# 1. Push a feature branch to GH -> CI.
# 2. On success:
#   a) Image is being tagged with 'staging'
#   b) Pushed to Tutum registry.
#   c) The tutum utility is called with --name=<your topic branch>.
#
# Caveats
#
# - If you lock in a tagged API image, that tag has to be pushed up-front.
# - Please delete your stack once it's been merged into production. At some
#   point this should be done programmatically, but for now, I say fuck it.
#
# Examples
#
# ./bin/deploy.rb linkedin-auth
#   => linkedin-auth.staging.yniche.com
#
# ./bin/deploy.rb production
#   => yniche.com

BRANCH_NAME = ARGV.shift || abort('! Branch name required.')
ENVIRONMENT = (BRANCH_NAME == 'production') ? 'production' : 'staging'
STACK_NAME  = "yniche-#{ENVIRONMENT}-#{BRANCH_NAME}"
LOCKED_API_TAG = ARGV.shift || (ENVIRONMENT == 'production' ? 'production' : 'latest')
API_IMAGE = 'tutum.co/yniche/api.yniche.com'

DEFINITION_VARIABLES = Hash.new { |hash, key| raise NoSuchKeyError.new(key) }
DEFINITION_VARIABLES['LOCKED_API_TAG'] = LOCKED_API_TAG
DEFINITION_VARIABLES['LOCKED_WEB_TAG'] = BRANCH_NAME
DEFINITION_VARIABLES['BRANCH'] = BRANCH_NAME

class NoSuchKeyError < StandardError
  attr_reader :key
  def initialize(key)
    @key = key
  end
end

def run(command)
  puts "~ $ #{command}"
  system(command) || abort("! Command failed.")
end

def deploy(stack_name, base_stackfile_path, stackfile_path)
  # 1. Build the image, tag it with yniche/yniche.com:<branch_name> and push it.
  #    We have autoredeploy, so the images gets restarted automatically.
  #    This has to happen first, otherwise deploying the stack will fail (no kidding, right?).
  tag = (BRANCH_NAME == 'master') ? 'latest' : BRANCH_NAME
  full_image_name = "yniche/yniche.com:#{DEFINITION_VARIABLES['LOCKED_WEB_TAG']}"
  # Assuming build already took place. This is just a deployment script.
  # run "docker build -t tutum.co/#{full_image_name} .."
  # If the following step fails, do docker-machine ssh yniche and remove the first
  # nameserver from /etc/resolv.conf. Not bloody joking, I really had to do that.
  #
  # Status 422 (PATCH https://dashboard.tutum.co/api/v1/stack/e8ddf38f-b0d5-4ec9-a0f1-d6b053de6342/).
  # Response: {"error": "There is a pending action 'Service Redeploy
  # (autoredeploy on push)' on this stack"}
  #
  # run "tutum push #{full_image_name}"
  # tutum push yniche/yniche.com:auth0

  # 2. Generate the stack definition from a base stack file.
  validate_api_tag_name(LOCKED_API_TAG)
  generate_stackfile(base_stackfile_path, stackfile_path)

  # 3. Create (or update if neccessary) a new stack with given name.
  stack = `tutum stack list`.split("\n").grep(Regexp.new("^#{stack_name}\s"))[0]
  if stack
    warn <<-EOF

Stack #{stack_name} already exist. If you just want to update the code:

  docker build -t tutum.co/yniche/yniche.com:#{BRANCH_NAME} ..
  docker push tutum.co/yniche/yniche.com:#{BRANCH_NAME}

Similarly, if you just want to update the API, rebuild & repush.
As long as you are not going to change the LOCKED_API_TAG,
all should be fine (although you need to restart the web service
manually, the restarts don't cascade up).

The rest will be taken care by Tutum autoredeploys.
Updating the stack definition makes sense only if

  * One of the services was changed, deleted or new one was added.
  * LOCKED_API_TAG was changed.

    EOF

    run "tutum stack update -f #{stackfile_path} #{stack.split(' ')[1]}"

    puts "Stack definition has been updated. Keep in mind that new services are not started automatically."
  else
    run "tutum stack up --name=#{stack_name} -f #{stackfile_path}"
  end
end

def validate_api_tag_name(locked_api_tag)
  api_image_data = JSON.parse(`tutum image inspect #{API_IMAGE}`)
  api_image_tags = api_image_data['tags'].map { |tag_url| tag_url.split('/').last }
  unless api_image_tags.include?(locked_api_tag)
    abort("! Tag #{locked_api_tag} doesn't exist in api.yniche.com. Available tags are: #{api_image_tags.inspect}")
  end
end

def generate_stackfile(base_stackfile_path, stackfile_path)
  base_definition = YAML.load_file(base_stackfile_path)
  base_definition.delete('defaults')
  definition = base_definition.to_yaml.gsub(/<%=\s*(\w+)\s*%>/) do |match|
    begin
      DEFINITION_VARIABLES[$1]
    rescue NoSuchKeyError => error
      abort("! Unsupported variable in #{base_stackfile_path}: #{error.key}")
    end
  end

  File.open(stackfile_path, 'w') do |file|
    file.write(definition)
  end
end

# Main.
if BRANCH_NAME == 'production'
  puts "~ Doing PRODUCTION deploy (locked to api.yniche.com:#{LOCKED_API_TAG})."
  puts <<-EOF

Checklist:
- Have you updated 'production' tag on yniche.com and pushed it?
- Have you updated 'production' tag on api.yniche.com and pushed it?

  EOF
  deploy('yniche-production', 'production.template.yml', 'production.yml')
else
  puts "~ Deploying #{BRANCH_NAME} to staging (locked to api.yniche.com:#{LOCKED_API_TAG})."
  deploy(STACK_NAME, 'staging.template.yml', 'staging.yml')
end
