require 'erb'
require 'tempfile'

SERVICE_TEMPLATE_PATH = "../templates/service_template.erb"
CONFIGURATION_TEMPLATE_PATH = "../templates/configuration_template.erb"

class TemplateUtil

 attr_reader :output

 # def initialize(path)
 #    @path = path
 # end

 def serviceTemplate(ports)
  @serviceFile = Tempfile.new("service") 
  @ports = ports
  @template = File.read(SERVICE_TEMPLATE_PATH)
  save(@serviceFile.path)
  @serviceFile.path
 end

 def configurationTemplate(role, ips, ports)
  @configurationFile = Tempfile.new("configuration") 
  @role=role
  @ips=ips
  @ports=ports
  @template = File.read(CONFIGURATION_TEMPLATE_PATH) 
  save(@configurationFile.path)
  @configurationFile.path
 end

 def render()
  ERB.new(@template, 0, "-", "@output").result(binding)	
 end

 def save(file)
  File.open(file, "w+") do |f|
    f.write(renderStream)
  end
 end

 private def renderStream()
  ERB.new(@template, 0, "-").result(binding)	
 end

end

#testing
#file = TemplateUtil.new()
#puts file.serviceTemplate(["2379","1395"])
#file.save("testService.sh")
#file.configurationTemplate("master",["172.17.4.101","172.17.4.102"], "8080")
#file.save("testConfiguration.sh")
