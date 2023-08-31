require "eventmachine"
require "securerandom"

module Minitest
  module Dispatch
    module Connection
      # This manages a conneciton to a consumer node
      class Adapter
        class TooManyRetryAttpempts < RuntimeError; end

        attr_accessor :port, :host, :connection, :connection_class, :timeout, :retry_count
        attr_reader :start_time, :connection_id, :cores

        def initialize(connection_class: Deferred, host: Settings::DEFAULT_HOST, port: Settings::DEFAULT_PORT,
                       timeout: Settings::DEFAULT_TIMEOUT)
          @connection       = nil
          @connected        = false
          @connection_class = connection_class
          @connection_id    = SecureRandom.hex(10)
          @cores            = 0
          @host             = host
          @port             = port.to_i
          @retry_count = 0
          @retry_interval   = Settings::DEFAULT_INTERVAL
          @timeout          = timeout

          raise "Timeout interval must be greater than 0" unless @timeout.positive?
        end

        def post_connect_setup
          @connection.add_callback(:unbind) { @connected = false }
          @connection.add_callback(:post_init) {} # TODO: post_init callback
          @connection.add_callback(:connect) do
            @retry_count = 0
            @connected = true
            @connection.send_object({ action: :config })
          end

          self
        end

        def timeout?
          Time.now - @start_time > @timeout
        end

        def reconnect
          if timeout?
            Logger.warn "Too many attepts to connect to #{@connection}, it was disconnected."
            @connected = false
            raise TooManyRetryAttpempts
          end

          @retry_count += 1
          Logger.warn "Reconnecting to \"#{@host}:#{@port}\" (retry #{@retry_count}) ..."
          @connection.reconnect(@host, @port)
        end

        def connect
          @start_time = Time.now
          Logger.info "Connecting to \"#{@host}:#{@port}\" ..."
          EventMachine.connect(@host, @port, @connection_class, { connection_id: @connection_id }) do |connection|
            @connection = connection
            post_connect_setup
          end
        end

        def connected?
          @connected
        end

        def disconnected?
          !connected?
        end
      end
    end
  end
end
