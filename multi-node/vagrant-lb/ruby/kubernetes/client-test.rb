#!/usr/bin/env ruby

require 'tempfile'
require 'openssl'
require 'erb'
require 'base64'

#Servicios de SALTO
SECRETS=File.expand_path("../../secrets/")
ENTITIES=File.expand_path("../../kubernetes-files/")
KUBECTL = File.expand_path("kubeclient.rb")

if File.exist?(KUBECTL)
  require KUBECTL
else
  abort ("missing required kubectl.rb file")
end

MASTER_HAPROXY_IP="172.17.4.202"
K8S_API_VER="v1"
SSL_OPTIONS = {
              client_cert: OpenSSL::X509::Certificate.new(File.read('../../ssl/admin.pem')),
              client_key:  OpenSSL::PKey::RSA.new(File.read('../../ssl/admin-key.pem')),
              ca_file:     '../../ssl/ca.pem',
              verify_ssl:  OpenSSL::SSL::VERIFY_PEER
            }

def create_client
 client = Kubeclient.new "https://#{MASTER_HAPROXY_IP}:443", "/api/" , K8S_API_VER, ssl_options: SSL_OPTIONS
 while (!client.api_valid?)
  puts "Kubernetes API server is down. Retrying connection in 10 secs."
  sleep(10)
 end
 client
end

ARGV.each do |a|
  case a
  when "create"
    client = create_client
    client.deploy_all SECRETS, ENTITIES
  when "delete"
    client = create_client
    client.delete_all ENTITIES
  when "update"
    client = create_client
    client.update_all ENTITIES
  when "custom"
    
    client = create_client
    client.create_entity "../../kubernetes-files/kubernetes-dashboard.yaml"
  else
    puts "Not implemented"
  end
end


