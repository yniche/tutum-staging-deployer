#!/usr/bin/env ruby

require 'yaml'
require 'json'

# Prerequisities
#
# 1. There's a DNS CNAME record pointing whatever URL Tutum exposed for
#    the staging load balancer.
#
# Workflow
#
# 1. Push a feature branch to GH -> CI.
# 2. On success:
#   a) Image is being tagged with the branch name (or 'latest' for master).
#   b) Image is pushed to the Tutum registry.
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
# ./bin/deploy.rb linkedin-auth/staging-web
#   => linkedin-auth.staging.yniche.com
#
# ./bin/deploy.rb master/staging-web:latest
#   => master.staging.yniche.com # Usually not necessary, master should == prod.

deployed_service = ARGV.shift || abort('! Deployed service name required.')

SHORT_NAME = deployed_service.split('/')[0] || abort('! Deployed service name is must be stack_name/deployed_service.')
STACK_NAME  = "yniche-#{SHORT_NAME}"
SOLO_STACK_NAME = 'yniche-staging-shared-services' # If you change this, you have to change your DNS, because the Tutum-exposed URL will change.
DEPLOYED_SERVICE = "#{deployed_service.split('/')[1]}.#{STACK_NAME}"

unless ARGV.empty?
  abort '! Only one argument (the name) expected.'
end

# LOCKED_API_TAG=auth0
DEFINITION_VARIABLES = Hash.new do |hash, key|
  if key.match(/^LOCKED_.+_TAG$/)
    hash[key] = ENV[key] || 'latest'
  else
    raise NoSuchKeyError.new(key)
  end
end

DEFINITION_VARIABLES['LOCKED_WEB_TAG'] = SHORT_NAME
DEFINITION_VARIABLES['SHORT_NAME'] = SHORT_NAME

class NoSuchKeyError < StandardError
  attr_reader :key
  def initialize(key)
    @key = key
  end

  def message
    "Unsupported key #{self.key}."
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
  tag = (SHORT_NAME == 'master') ? 'latest' : SHORT_NAME
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
  if base_stackfile_path
    generate_stackfile(base_stackfile_path, stackfile_path)
  end

  # 3. Create (or update if neccessary) a new stack with given name.
  stacks = `tutum stack list`.split("\n").grep(Regexp.new("^#{stack_name}\s"))
  stack = stacks.select { |stack_line| ! stack_line.match(/Terminated/) }[0]
  if stack
#     warn <<-EOF
#
# Stack #{stack_name} already exist. If you just want to update the code:
#
#   docker build -t tutum.co/yniche/yniche.com:#{SHORT_NAME} ..
#   docker push tutum.co/yniche/yniche.com:#{SHORT_NAME}
#
# Similarly, if you just want to update the API, rebuild & repush.
# As long as you are not going to change the LOCKED_API_TAG,
# all should be fine (although you need to restart the web service
# manually, the restarts don't cascade up).
#
# The rest will be taken care by Tutum autoredeploys.
# Updating the stack definition makes sense only if
#
#   * One of the services was changed, deleted or new one was added.
#   * LOCKED_API_TAG was changed.
#
#     EOF

    run "tutum stack update -f #{stackfile_path} #{stack.split(' ')[1]}"

    puts "Stack definition has been updated. Keep in mind that new services are not started automatically."
  else
    run "tutum stack up --name=#{stack_name} -f #{stackfile_path}"
  end
end

# TODO: Rewrite to be generic. (List your repos | filter)
# API_IMAGE = 'tutum.co/yniche/api.yniche.com' # Not generic.
# def validate_api_tag_name(locked_api_tag)
#   api_image_data = JSON.parse(`tutum image inspect #{API_IMAGE}`)
#   api_image_tags = api_image_data['tags'].map { |tag_url| tag_url.split('/').last }
#   unless api_image_tags.include?(locked_api_tag)
#     abort("! Tag #{locked_api_tag} doesn't exist in api.yniche.com. Available tags are: #{api_image_tags.inspect}")
#   end
# end

def generate_stackfile(base_stackfile_path, stackfile_path)
  base_definition = YAML.load_file(base_stackfile_path)
  base_definition.delete('defaults')
  definition = base_definition.to_yaml.gsub(/"?<%=\s*(\w+)\s*%>"?/) do |match|
    begin
      value = DEFINITION_VARIABLES[$1]
      puts "  ~> Replacing #{$1} with #{value.inspect}."
      value
    rescue NoSuchKeyError => error
      abort("! Error in #{base_stackfile_path}: #{error.message}")
    end
  end

  File.open(stackfile_path, 'w') do |file|
    file.write(definition)
  end
end

# Main.
# No longer providing production deployments.
# if SHORT_NAME == 'production'
#   puts "~ Doing PRODUCTION deploy (locked to api.yniche.com:#{LOCKED_API_TAG})."
#   puts <<-EOF
#
# Checklist:
# - Have you updated 'production' tag on yniche.com and pushed it?
# - Have you updated 'production' tag on api.yniche.com and pushed it?
#
#   EOF
#   deploy('yniche-production', 'production.template.yml', 'production.yml')
puts "~ 1. Initial deployment to make sure the DB is there (we link it from the web & api services)."

lb_links = begin
  load_balancer_info = JSON.parse(`tutum service inspect staging-lb.yniche-staging-shared-services`)
  ids = load_balancer_info['linked_to_service'].map { |node| node['to_service'].split('/').last }
  ids.map do |id|
    # To get the full stack_name.service_name.
    public_dns = JSON.parse(`tutum service inspect #{id}`)['public_dns']
    service_name, stack_name = public_dns.split('.')[0..1]
    label = service_name.sub(/^staging-/, '')
    "#{service_name}.#{stack_name}:#{label}-#{stack_name}"
  end
rescue
  Array.new
end

DEFINITION_VARIABLES['LB_LINKS'] = lb_links.inspect

if File.exist?('staging.solo.template.yml')
  deploy(SOLO_STACK_NAME, 'staging.solo.template.yml', 'staging.solo.yml')
else
  puts '~ File staging.solo.template.yml has not been found, assuming the common services are up and running already.'
end

puts "~ 2. Deploying #{SHORT_NAME} to staging"
deploy(STACK_NAME, 'staging.stack.template.yml', "#{STACK_NAME}.yml")
puts "Variables: #{DEFINITION_VARIABLES.inspect})." # Has to be a posteriori due to the hash default block setting vars.

puts '~ 3. Stack deployed. Linking to the load balancer ...'
# if File.exist?('staging.solo.template.yml')

  service_name, stack_name = DEPLOYED_SERVICE.split('.')
  label = service_name.sub(/^staging-/, '')
  named_deployed_service = "#{service_name}.#{stack_name}:#{label}-#{stack_name}"
  p DEFINITION_VARIABLES
  linked_services = DEFINITION_VARIABLES.reduce(Array.new) do |buffer, (key, value)|
    if key.match(/^LOCKED_(.+)_TAG$/)
      service_name = "staging-#{$1.downcase}"
      buffer << "#{service_name}.#{stack_name}:#{$1.downcase}-#{stack_name}"
    end

    buffer
  end
  DEFINITION_VARIABLES['LB_LINKS'] = (((lb_links + linked_services) << named_deployed_service).uniq).inspect
  deploy(SOLO_STACK_NAME, 'staging.solo.template.yml', 'staging.solo.yml')
# else
#   # Actually I realised this is unnecessary. We deploy from one place only and
#   # that's the frontend. API just pushes new Docker tags.
#   #
#   # There's 'None' as the first line. God knows why.
#   `tutum stack export yniche-staging-shared-services > export.tmp.yml`
#   valid_yaml = File.readlines('export.tmp.yml')[1..-1].join('')
#   stack = YAML.load(valid_yaml)
#   service_name, stack_name = DEPLOYED_SERVICE.split('.')
#   stack['staging-lb']['links'] = stack['staging-lb']['links'].push("#{service_name}.#{stack_name}:#{stack_name}").uniq
#   File.write('staging.solo.yml', 'w') { |f| f.write(stack.to_yaml) }
#   deploy(SOLO_STACK_NAME, nil, 'staging.solo.yml')
# end

# This shouldn't be necessary. LB has role global and should reconfigure itself from the Tutum API, but it's not happening.
run 'tutum service redeploy staging-lb.yniche-staging-shared-services'
system 'sudo killall -HUP mDNSResponder' ## Why the bloody fuck do I need this?

puts '~ Done and done! Now you have to wait for a bit. No idea why, but it will take about 5 min. Clearing the DNS cache does not help. EDIT - it does, but you have to wait a bit apparently. Only for the first service though, from there on it works immediately.'
