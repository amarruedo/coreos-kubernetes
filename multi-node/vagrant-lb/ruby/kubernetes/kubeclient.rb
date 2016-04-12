require 'json'
require 'yaml'
require 'rest-client'
require 'base64'
require 'erb'

class Kubeclient

    attr_reader :api_endpoint
    attr_reader :ssl_options
    attr_reader :auth_options
    attr_reader :headers

    ENTITY_TYPES = %w(Pod Service ReplicationController Node Event Endpoint
                      Namespace Secret ResourceQuota LimitRange PersistentVolume
                      PersistentVolumeClaim ComponentStatus ServiceAccount)

    class Basicerb
     attr_reader :out
     def initialize(secrets)
      @secrets = secrets
     end

     def render temp
      ERB.new(File.read(temp),0, "-", "@out").result(binding)
     end
    end

    def initialize(
      uri,
      path,
      version = nil,
      ssl_options: {
        client_cert: nil,
        client_key: nil,
        ca_file: nil,
        cert_store: nil,
        verify_ssl: OpenSSL::SSL::VERIFY_PEER
      },
      auth_options: {
        username: nil,
        password: nil,
        bearer_token: nil,
        bearer_token_file: nil
      },
      socket_options: {
        socket_class: nil,
        ssl_socket_class: nil
      }
    )
      validate_auth_options(auth_options)
      handle_uri(uri, path)

      @api_version = version
      @headers = {}
      @ssl_options = ssl_options
      @auth_options = auth_options
      @socket_options = socket_options

      if auth_options[:bearer_token]
        bearer_token(@auth_options[:bearer_token])
      elsif auth_options[:bearer_token_file]
        validate_bearer_token_file
        bearer_token(File.read(@auth_options[:bearer_token_file]))
      end
    end

    def handle_exception
      yield
    rescue Exception => e 
        puts e.message
    rescue RestClient::Exception => e
      begin   
        json_error_msg = JSON.parse(e.response || '') || {}
      rescue JSON::ParserError
        json_error_msg = {}
      end
      err_message = json_error_msg['message'] || e.message
      puts 'HTTP status code ' + e.http_code.to_s + ', ' + err_message 
    end

    def handle_uri(uri, path)
      fail ArgumentError, 'Missing uri' if uri.nil?
      @api_endpoint = (uri.is_a? URI) ? uri : URI.parse(uri)
      @api_endpoint.path = path if @api_endpoint.path.empty?
      @api_endpoint.path = @api_endpoint.path.chop \
                         if @api_endpoint.path.end_with? '/'
    end

    def build_namespace_prefix(namespace)
      namespace.to_s.empty? ? "namespaces/default/" : "namespaces/#{namespace}/"
    end

    def pluralize_entity(entity_name)
      return entity_name + 's' if entity_name.end_with? 'quota'
      pluralize entity_name
    end

    def create_rest_client(path = nil)
      path ||= @api_endpoint.path
      options = {
        ssl_ca_file: @ssl_options[:ca_file],
        ssl_cert_store: @ssl_options[:cert_store],
        verify_ssl: @ssl_options[:verify_ssl],
        ssl_client_cert: @ssl_options[:client_cert],
        ssl_client_key: @ssl_options[:client_key],
        user: @auth_options[:username],
        password: @auth_options[:password]
      }
      RestClient::Resource.new(@api_endpoint.merge(path).to_s, options)
    end

    def rest_client
      @rest_client ||= begin
        create_rest_client("#{@api_endpoint.path}/#{@api_version}")
      end
    end

    def get_entity(entity_type, name, namespace = nil)
      ns_prefix = build_namespace_prefix(namespace)
      response = handle_exception do
        rest_client[ns_prefix + resource_name(entity_type) + "/#{name}"]
        .get(@headers)
      end
      begin
       result = JSON.parse(response)
       puts result
      rescue
       json_error_msg = {}
      end
    end

    def delete_entity(entity_type, name, namespace = nil)
      ns_prefix = build_namespace_prefix(namespace)
      handle_exception do
        rest_client[ns_prefix + resource_name(entity_type) + "/#{name}"]
          .delete(@headers)
      end
    end

    def create_entity(entity_config_path)
      documents = YAML.load_stream(IO.readlines(File.expand_path(entity_config_path))[1..-1].join)
      documents.each do |data|
        puts data.inspect
        ns_prefix = build_namespace_prefix(data['metadata']['namespace'])
        entity_type = data['kind']
        @headers['Content-Type'] = 'application/json'
        response = handle_exception do
         rest_client[ns_prefix + resource_name(entity_type)]
         .post(JSON.dump(data), @headers)
        end
        begin
         result = JSON.parse(response)
        rescue
         json_error_msg = {}
        end
      end
    end

    def resource_name(entity_type)
      pluralize_entity entity_type.downcase
    end

    def api_valid?
      result = api
      result.is_a?(Hash) && (result['versions'] || []).include?(@api_version)
    end

    def api
      response = handle_exception do
        create_rest_client.get(@headers)
      end
      begin
       result = JSON.parse(response)
      rescue
       json_error_msg = {}
      end
    end

    def load_secrets(secrets_path, entities_path)
     secret_hash = Hash.new
     secrets = File.expand_path(secrets_path)
     entities = File.expand_path(entities_path)

     Dir.foreach(secrets) do |item|
      next if item == '.' or item == '..'
      File.foreach(File.expand_path(secrets+"/"+item)) do |line|
       secret_hash[item] = Base64.strict_encode64(line)
      end
     end
     secret_hash
    end

    def deploy_all(secrets_path, entities_path)
      secrets = load_secrets(secrets_path, entities_path)
      entities = File.expand_path(entities_path)
      Dir.foreach(entities) do |item|
        next if item == '.' or item == '..'
        complete_path = File.expand_path(entities+"/"+item)
        if File.extname(item) == ".erb"
          renderer = Basicerb.new(secrets)
          template_file = Tempfile.new("#{item}")
          renderer.render(complete_path)
          template_file.write(renderer.out)
          template_file.close
          create_entity template_file.path
          template_file.unlink
        elsif File.extname(item) == ".yml"
          create_entity complete_path
        end
      end 
    end

    # def delete_all()
    #   ns_prefix = build_namespace_prefix(namespace)
    #   handle_exception do
    #     rest_client[ns_prefix + resource_name(entity_type) + "/#{name}"]
    #       .delete(@headers)
    #   end
    # end

    private

    def bearer_token(bearer_token)
      @headers ||= {}
      @headers[:Authorization] = "Bearer #{bearer_token}"
    end

    def validate_auth_options(opts)
      # maintain backward compatibility:
      opts[:username] = opts[:user] if opts[:user]

      if [:bearer_token, :bearer_token_file, :username].count { |key| opts[key] } > 1
        fail(ArgumentError, 'Invalid auth options: specify only one of username/password,' \
             ' bearer_token or bearer_token_file')
      elsif [:username, :password].count { |key| opts[key] } == 1
        fail(ArgumentError, 'Basic auth requires both username & password')
      end
    end

    def validate_bearer_token_file
      msg = "Token file #{@auth_options[:bearer_token_file]} does not exist"
      fail ArgumentError, msg unless File.file?(@auth_options[:bearer_token_file])

      msg = "Cannot read token file #{@auth_options[:bearer_token_file]}"
      fail ArgumentError, msg unless File.readable?(@auth_options[:bearer_token_file])
    end

    def pluralize(entity_name)
      return entity_name + 's' if entity_name != "componentstatus"

    end

end