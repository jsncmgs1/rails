require 'soap/rpc/driver'
require 'uri'

module ActionWebService # :nodoc:
  module Client # :nodoc:

    # Implements SOAP client support (using RPC encoding for the messages).
    #
    # ==== Example Usage
    #
    #   class PersonAPI < ActionWebService::API::Base
    #     api_method :find_all, :returns => [[Person]]
    #   end
    #
    #   soap_client = ActionWebService::Client::Soap.new(PersonAPI, "http://...")
    #   persons = soap_client.find_all
    #
    class Soap < Base

      # Creates a new web service client using the SOAP RPC protocol.
      #
      # +api+ must be an ActionWebService::API::Base derivative, and
      # +endpoint_uri+ must point at the relevant URL to which protocol requests
      # will be sent with HTTP POST.
      #
      # Valid options:
      # [<tt>:service_name</tt>]    If the remote server has used a custom +wsdl_service_name+
      #                             option, you must specify it here
      def initialize(api, endpoint_uri, options={})
        super(api, endpoint_uri)
        @service_name = options[:service_name] || 'ActionWebService'
        @namespace = "urn:#{@service_name}" 
        @mapper = ActionWebService::Protocol::Soap::SoapMapper.new(@namespace)
        @protocol = ActionWebService::Protocol::Soap::SoapProtocol.new(@mapper)
        @soap_action_base = options[:soap_action_base]
        @soap_action_base ||= URI.parse(endpoint_uri).path
        @driver = create_soap_rpc_driver(api, endpoint_uri)
      end

      protected
        def perform_invocation(method_name, args)
          @driver.send(method_name, *args)
        end

        def soap_action(method_name)
          "#{@soap_action_base}/#{method_name}"
        end

      private
        def create_soap_rpc_driver(api, endpoint_uri)
          @mapper.map_api(api)
          driver = SoapDriver.new(endpoint_uri, nil)
          driver.mapping_registry = @mapper.registry
          api.api_methods.each do |name, info|
            public_name = api.public_api_method_name(name)
            qname = XSD::QName.new(@namespace, public_name)
            action = soap_action(public_name)
            expects = info[:expects]
            returns = info[:returns]
            param_def = []
            i = 1
            if expects
              expects.each do |klass|
                param_name = klass.is_a?(Hash) ? klass.keys[0] : "param#{i}"
                param_klass = lookup_class(klass)
                mapping = @mapper.lookup(param_klass)
                param_def << ['in', param_name, mapping.registry_mapping]
                i += 1
              end
            end
            if returns
              mapping = @mapper.lookup(lookup_class(returns[0]))
              param_def << ['retval', 'return', mapping.registry_mapping]
            end
            driver.add_method(qname, action, name.to_s, param_def)
          end
          driver
        end

        class SoapDriver < SOAP::RPC::Driver # :nodoc:
          def add_method(qname, soapaction, name, param_def)
            @proxy.add_rpc_method(qname, soapaction, name, param_def)
            add_rpc_method_interface(name, param_def)
          end
        end
    end
  end
end
