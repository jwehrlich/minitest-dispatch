require "eventmachine"
require "securerandom"

module Minitest
  module Dispatch
    module Connection
      class Adapter
        attr_accessor :port, :host, :connection, :connection_class, :timeout, :reconnects_count
        attr_reader :start_time, :connection_id, :cores

        def initialize(connection_class: Deferred, host: Settings::DEFAULT_HOST, port: Settings::DEFAULT_PORT,
                       timeout: Settings::DEFAULT_TIMEOUT)
          @connection       = nil
          @connection_class = connection_class
          @connection_id    = SecureRandom.hex(10)
          @cores            = 0
          @host             = host
          @port             = port.to_i
          @reconnects_count = 0
          @retry_interval   = Settings::DEFAULT_INTERVAL
          @timeout          = timeout

          raise "Timeout interval must be greater than 0" unless @timeout.positive?
        end

        def post_connect_setup
          @connection.add_callback(:post_init) {}
          @connection.add_callback(:connect) do
            # This notifies the manager that the consumer was connected to. It also provides config of self
            @connection.send_object({ action: :config })
          end

          @connection.add_callback(:unbind) do |reason|
            if can_retry?(reason) && not_timeout?
              EventMachine::Timer.new(@retry_interval) { reconnect }
            else
              Logger.warn "Connection #{@connection} unbinded with reason \"#{reason}\"."
              @connection = nil
            end
          end

          self
        end

        def can_retry?(reason)
          reason == Errno::ECONNREFUSED
        end

        def not_timeout?
          Time.now - @start_time <= @timeout
        end

        def reconnect
          @reconnects_count += 1
          Logger.warn "Reconnecting to \"#{@host}:#{@port}\" (retry #{@reconnects_count}) ..."
          @connection.reconnect(@host, @port)
        end

        def connect
          @start_time = Time.now
          Logger.info "Connecting to \"#{@host}:#{@port}\" ..."
          EM.connect(@host, @port, @connection_class, { connection_id: @connection_id }) do |connection|
            @connection = connection
            post_connect_setup
          end
        end
      end
    end
  end
end
