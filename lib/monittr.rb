require 'nokogiri'
require 'rest-client'
require 'ostruct'
require 'timeout'

module Monittr
  # Represents a cluster of monitored instances.
  # Pass an array of URLs to the constructor.
  #
  class Cluster
    attr_reader :servers

    def initialize(urls = [])
      @servers = urls.map { |url| Server.fetch(url) }
    end
  end

  # Represents one monitored instance
  #
  class Server
    attr_reader :url, :xml, :system, :files, :filesystems, :processes, :hosts

    def initialize(url, xml)
      @url = url
      @xml = Nokogiri::XML(xml)
      if (error = @xml.xpath('error').first)
        @system = Services::Base.new(
          name: error.attributes['name'].content,
          message: error.attributes['message'].content,
          status: 3
        )
        @filesystems = []
        @files       = []
        @processes   = []
        @hosts       = []
      else
        @system      = Services::System.new(@xml.xpath('//service[@type=5]').first)
        @filesystems = @xml.xpath('//service[@type=0]').map { |data| Services::Filesystem.new(data) }
        @files       = @xml.xpath('//service[@type=2]').map { |data| Services::File.new(data) }
        @processes   = @xml.xpath('//service[@type=3]').map { |data| Services::Process.new(data) }
        @hosts       = @xml.xpath('//service[@type=4]').map { |data| Services::Host.new(data) }
      end
    end

    # Retrieve Monit status XML from the URL
    #
    def self.fetch_by_url(url = 'http://admin:monit@localhost:2812')
      Timeout::timeout(1) do
        monit_url  = url
        monit_url += '/' unless url =~ %r{/$}
        monit_url += '_status?format=xml' unless url =~ /_status\?format=xml$/
        new url, RestClient.get(monit_url)
      end
    rescue Exception => e
      new url, %(<error status="3" name="#{e.class}" message="#{e.message}" />)
    end

    # Retrieve Monit status XML from the params hash
    #
    def self.fetch_by_hash(hostname = 'localhost', port: 2812,
                           username: 'admin', password: 'monit',
                           schema: 'http',
                           ssl_cert: nil, ssl_key: nil, ssl_ca: nil)
      Timeout::timeout(1) do
        monit_url  = %(#{schema}://#{username}:#{password}@#{hostname}:#{port}/)
        monit_url += '_status?format=xml' unless url =~ /_status\?format=xml$/

        if schema == 'https+'
          new url,
              RestClient::Resource.new(
                monit_url,
                ssl_client_cert: ssl_cert,
                ssl_client_key: ssl_key,
                ssl_ca_file: ssl_ca,
                verify_ssl: OpenSSL::SSL::VERIFY_PEER
              ).get
        else
          new url, RestClient.get(monit_url)
        end
      end
    rescue Exception => e
      new url, %(<error status="3" name="#{e.class}" message="#{e.message}" />)
    end

    def inspect
      %(<#{self.class} name="#{system.name}" status="#{system.status}" \
      message="#{system.message}">)
    end
  end

  module Services
    class Base < OpenStruct
      TYPES = {
        0 => 'Filesystem',
        1 => 'Directory',
        2 => 'File',
        3 => 'Daemon',
        4 => 'Connection',
        5 => 'System'
      }.freeze

      def load
        # Note: the `load` gives some headaches, let's be explicit
        @table[:load]
      end

      def value(matcher, converter = :to_s)
        @xml.xpath(matcher).first.content.send(converter)
      rescue StandardError
        nil
      end

      def inspect
        %(<#{self.class} name="#{name}" status="#{status}" message="#{message}">)
      end
    end

    # A "system" service in Monit
    #
    # <service type="5">
    #
    class System < Base
      def initialize(xml)
        @xml = xml
        super(
          {
            name:      value('name'),
            os:        value('//platform/name'),
            osversion: value('//platform/release'),
            arch:      value('//platform/machine'),
            memtotal:  value('//platform/memory',     :to_i),
            swaptotal: value('//platform/swap',       :to_i),
            cputotal:  value('//platform/cpu',        :to_i),
            status:    value('status',                :to_i),
            monitored: value('monitor',               :to_i),
            load:      value('system/load/avg01',     :to_f),
            cpu:       value('system/cpu/user',       :to_f),
            memory:    value('system/memory/percent', :to_f),
            swap:      value('system/swap/percent',   :to_f),
            uptime:    value('//server/uptime',       :to_i)
          }
        )
      end
    end

    # A "file" service in Monit
    #
    # <service type="2">
    #
    class File < Base
      def initialize(xml)
        @xml = xml
        super(
          {
            name:      value('name'),
            status:    value('status',    :to_i),
            monitored: value('monitor',   :to_i),
            uid:       value('uid',       :to_i),
            gid:       value('gid',       :to_i),
            size:      value('size',      :to_i),
            timestamp: value('timestamp', :to_i)
          }
        )
      end
    end

    # A "filesystem" service in Monit
    #
    # http://mmonit.com/monit/documentation/monit.html#filesystem_flags_testing
    #
    # <service type="0">
    #
    class Filesystem < Base
      def initialize(xml)
        @xml = xml
        super(
          {
            name:          value('name'),
            status:        value('status',        :to_i),
            monitored:     value('monitor',       :to_i),
            percent:       value('block/percent', :to_f),
            usage:         value('block/usage'),
            total:         value('block/total'),
            inode_percent: value('inode/percent', :to_f),
            inode_usage:   value('inode/usage'),
            inode_total:   value('inode/total')
          }
        )
      rescue Exception => e
        puts "ERROR: #{e.class} -- #{e.message}, In: #{e.backtrace.first}"
        super(
          {
            name:    'Error',
            status:  3,
            message: e.message
          }
        )
      end
    end

    # A "process" service in Monit
    #
    # http://mmonit.com/monit/documentation/monit.html#pid_testing
    #
    # <service type="3">
    #
    class Process < Base
      def initialize(xml)
        @xml = xml
        super(
          {
            name:          value('name'),
            status:        value('status',              :to_i),
            monitored:     value('monitor',             :to_i),
            pid:           value('pid',                 :to_i),
            uptime:        value('uptime',              :to_i),
            children:      value('children',            :to_i),
            memory:        value('memory/percent',      :to_f),
            cpu:           value('cpu/percent',         :to_i),
            total_memory:  value('memory/percenttotal', :to_f),
            total_cpu:     value('cpu/percenttotal',    :to_i),
            response_time: value('port/responsetime',   :to_i)
          }
        )
      rescue Exception => e
        puts "ERROR: #{e.class} -- #{e.message}, In: #{e.backtrace.first}"
        super(
          {
            name: 'Error',
            status: 3,
            message: e.message
          }
        )
      end
    end

    # A "host" service in Monit
    #
    # http://mmonit.com/monit/documentation/monit.html#connection_testing
    #
    # <service type="4">
    #
    class Host < Base
      def initialize(xml)
        @xml = xml
        super(
          {
            name:          value('name'),
            status:        value('status',  :to_i),
            monitored:     value('monitor', :to_i),
            response_time: value('port/responsetime')
          }
        )
      rescue Exception => e
        puts "ERROR: #{e.class} -- #{e.message}, In: #{e.backtrace.first}"
        super(
          {
            name:    'Error',
            status:  3,
            message: e.message
          }
        )
      end
    end
  end
end
