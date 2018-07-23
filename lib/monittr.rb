require 'nokogiri'
require 'rest-client'
require 'timeout'
require 'monittr/services'

module Monittr
  # Represents a cluster of monitored instances.
  # Pass an array of URLs to the constructor.
  #
  class Cluster
    attr_reader :servers

    def initialize(serverlist = [])
      @servers = serverlist.map { |server| Server.fetch server }
    end
  end

  # Represents one monitored instance
  #
  class Server
    attr_reader :server_opts, :xml, :system, :files,
                :filesystems, :processes, :hosts

    def initialize(server_opts, xml)
      @server_opts = server_opts
      @xml = Nokogiri::XML(xml)
      @filesystems, @files, @processes, @hosts = [], [], [], []
      if (error = @xml.xpath('error').first)
        @system = Services::Base.new({ name: error['name'],
                                       message: error['message'],
                                       status: 3 }, skip_fill: true)
      else
        fill_services
      end
    end

    def fill_services
      service_fields = { 0 => @filesystems, 2 => @files,
                         3 => @processes, 4 => @hosts }

      @xml.xpath('//service').each do |service|
        s_type = service['type'].to_i
        # System service (type == 5) is always the only one, but there may be
        # many services of other types.
        if s_type == 5
          @system = Services::System.new(service)
        else
          service_fields[s_type] << Services::SERVICE_TYPES[s_type].new(service)
        end
      end
    end

    def self.prepare_restclient_options(server)
      ssl_opts = server[:ssl_opts]
      connection_opts = { user: server[:username], password: server[:password] }

      if server[:schema] == 'https' && !ssl_opts.nil?
        connection_opts.merge!(
          ssl_client_cert: ssl_opts[:cert], ssl_client_key: ssl_opts[:key],
          ssl_ca_file: ssl_opts[:ca],
          verify_ssl: ssl_opts[:verify] ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
        )
      end

      connection_opts
    end

    # Retrieve Monit status XML from the params hash
    #
    def self.fetch(hostname: 'localhost', port: 2812,
                   username: 'admin', password: 'monit',
                   schema: 'http', ssl_opts: nil)
      server = { hostname: hostname, port: port, username: username,
                 password: password, schema: schema, ssl_opts: ssl_opts }

      Timeout.timeout(1) do
        monit_url = %(#{schema}://#{hostname}:#{port}/_status?format=xml)
        connection_opts = prepare_restclient_options(server)

        new server, RestClient::Resource.new(monit_url, connection_opts).get
      end
    rescue Exception => e
      new server,
          %(<error status="3" name="#{e.class}" message="#{e.message}" />)
    end

    def inspect
      format(
        %(<%<cls>s name="%<name>s" status="%<status>s" message="%<msg>s">),
        cls: self.class,
        name: system.name,
        status: system.status,
        msg: system.message
      )
    end

    def to_h(verbose: false)
      hash = { name: system.name, status: system.status,
               system: @system.to_h, files: @files.map(&:to_h),
               filesystems: @filesystems.map(&:to_h),
               processes: @processes.map(&:to_h),
               hosts: @hosts.map(&:to_h) }
      if verbose
        hash[:xml] = @xml
        hash[:server_opts] = @server_opts
      end
      hash
    end
  end
end
