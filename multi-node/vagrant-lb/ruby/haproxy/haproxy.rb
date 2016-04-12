require 'erb'

SERVICE_TEMPLATE_PATH = File.expand_path("ruby/haproxy/service-template.erb")
CONFIGURATION_TEMPLATE_PATH = File.expand_path("ruby/haproxy/configuration-template.erb")

class TemplateUtil

 attr_reader :configuration, :service

 def initialize(role, ips, ports)
  @role=role
  @ips=ips
  @ports = ports
 end

 def fillTemplates()
  ERB.new(File.read(CONFIGURATION_TEMPLATE_PATH), 0, "-", "@configuration").result(binding)
  ERB.new(File.read(SERVICE_TEMPLATE_PATH), 0, "-", "@service").result(binding)
 end

end

