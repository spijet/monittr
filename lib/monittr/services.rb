require 'nokogiri'
require 'ostruct'

module Monittr
  module Services
    # Basic "skeleton" of Monit service.
    # Includes all common methods for all services.
    # Refer to other classes for their respective fieldsets.
    class Base < OpenStruct
      def initialize(data, skip_fill: false)
        if skip_fill
          super data
        else
          @xml = data
          super fill_values(self.class::FIELDS)
        end
      rescue Exception => e
        STDERR.puts format('Monittr error: %<cls>s -- %<msg>s, in: %<bt>s',
                           cls: e.class, msg: e.message, bt: e.backtrace.first)
        super({ name: 'Error', status: 3, message: e.message })
      end

      # Retrieve single field value from XML element
      def value(matcher, converter = :to_s)
        @xml.xpath(matcher).first.content.send(converter)
      rescue StandardError
        nil
      end

      # Retrieve a set of field values from XML
      def fill_values(fields)
        Hash[
          fields.map do |field, source, converter = :to_s|
            [field, value(source, converter)]
          end
        ]
      end

      def inspect
        format(
          '<%<cls>s name="%<name>s" status="%<status>s" message="%<msg>s">',
          cls: self.class, name: name, status: status, msg: message
        )
      end
    end

    # A "system" service in Monit
    #
    # <service type="5">
    #
    class System < Base
      FIELDS = [
        [:name,      'name'],
        [:os,        '//platform/name'],
        [:osversion, '//platform/release'],
        [:arch,      '//platform/machine'],
        [:memtotal,  '//platform/memory',      :to_i],
        [:swaptotal, '//platform/swap',        :to_i],
        [:cputotal,  '//platform/cpu',         :to_i],
        [:status,    'status',                 :to_i],
        [:monitored, 'monitor',                :to_i],
        [:la01,      'system/load/avg01',      :to_f],
        [:la05,      'system/load/avg05',      :to_f],
        [:la15,      'system/load/avg15',      :to_f],
        [:cpuuser,   'system/cpu/user',        :to_f],
        [:cpusystem, 'system/cpu/system',      :to_f],
        [:cpuwait,   'system/cpu/wait',        :to_f],
        [:mempct,    'system/memory/percent',  :to_f],
        [:swappct,   'system/swap/percent',    :to_f],
        [:memused,   'system/memory/kilobyte', :to_f],
        [:swapused,  'system/swap/kilobyte',   :to_f],
        [:uptime,    '//server/uptime',        :to_i]
      ].freeze
    end

    # A "file" service in Monit
    #
    # <service type="2">
    #
    class File < Base
      FIELDS = [
        [:name, 'name'],
        [:status,    'status',    :to_i],
        [:monitored, 'monitor',   :to_i],
        [:uid,       'uid',       :to_i],
        [:gid,       'gid',       :to_i],
        [:size,      'size',      :to_i],
        [:timestamp, 'timestamp', :to_i]
      ].freeze
    end

    # A "filesystem" service in Monit
    #
    # http://mmonit.com/monit/documentation/monit.html#filesystem_flags_testing
    #
    # <service type="0">
    #
    class Filesystem < Base
      FIELDS = [
        [:name,          'name'],
        [:flags,         'fsflags'],
        [:status,        'status',        :to_i],
        [:monitored,     'monitor',       :to_i],
        [:percent,       'block/percent', :to_f],
        [:usage,         'block/usage'],
        [:total,         'block/total'],
        [:inode_percent, 'inode/percent', :to_f],
        [:inode_usage,   'inode/usage'],
        [:inode_total,   'inode/total']
      ].freeze
    end

    # A "process" service in Monit
    #
    # http://mmonit.com/monit/documentation/monit.html#pid_testing
    #
    # <service type="3">
    #
    class Process < Base
      FIELDS = [
        [:name,          'name'],
        [:status,        'status',              :to_i],
        [:monitored,     'monitor',             :to_i],
        [:pid,           'pid',                 :to_i],
        [:uptime,        'uptime',              :to_i],
        [:children,      'children',            :to_i],
        [:memory,        'memory/percent',      :to_f],
        [:cpu,           'cpu/percent',         :to_i],
        [:total_memory,  'memory/percenttotal', :to_f],
        [:total_cpu,     'cpu/percenttotal',    :to_i],
        [:response_time, 'port/responsetime',   :to_f]
      ].freeze
    end

    # A "host" service in Monit
    #
    # http://mmonit.com/monit/documentation/monit.html#connection_testing
    #
    # <service type="4">
    #
    class Host < Base
      FIELDS = [
        [:name,          'name'],
        [:status,        'status',  :to_i],
        [:monitored,     'monitor', :to_i],
        [:response_time, 'port/responsetime', :to_f]
      ].freeze
    end

    SERVICE_TYPES = {
      0 => Filesystem,
      # Not implemented for now:
      # 1 => Directory,
      2 => File,
      3 => Process,
      4 => Host,
      5 => System
    }.freeze
  end
end
