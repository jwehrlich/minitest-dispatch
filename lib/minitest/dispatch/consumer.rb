require "eventmachine"

# TODO: if get disconnected, stay alive for a while to see it gets reconnected. Either kill all
# childs and recreate or save states for reconnection

module Minitest
  module Dispatch
    class Consumer
      def self.start(options)
        Logger.info "staring consumer..."
        Settings.disable_autorun_tests
        @instance ||= new(options)
        @instance.run
      end

      def initialize(options)
        @connection = nil
        @workspace = options[:workspace]
        @cores = options[:cores]
        @host = options[:host]
        @port = options[:port]

        @process_manager = Process::Manager.new(cores: @cores)
        @process_manager.add_callback(:failed_to_process) do |object|
          send_object_data({
            action: :reschedule_test,
            test_case: object[:test_case],
            options: object[:options]
          })
        end
        @process_manager.add_callback(:test_finished) do |result|
          send_object_data({ action: :test_result, result: result })
        end
      end

      def run
        Signal.trap("SIGINT") do
          @process_manager.stop(is_trap: true)
          @connection.close_connection_after_writing unless @connection.nil?
        end

        Signal.trap("EXIT") do
          @process_manager.stop(is_trap: true)
          @connection.close_connection_after_writing unless @connection.nil?
          EventMachine.stop_event_loop
        end

        EM.run do
          Logger.info "Start event machine server: #{@host}:#{@port}"
          @process_manager.start

          EM.start_server(@host, @port, Connection::Deferred) do |connection|
            @connection = connection
            Logger.info "Connection with manager established: #{@connection.inspect}"

            @connection.add_callback(:post_init) {}

            @connection.add_callback(:receive_object) do |object|
              process_object(object)
            end

            @connection.add_callback(:unbind) do
              @process_manager.stop
              EM.stop
            end
          end
        end
      end

      def process_object(object)
        case object[:action]
        when :config
          # Send the details regarding processing availability for node
          Logger.info "Config request: #{object}"
          @connection.instance_variable_set(:@connection_id, object[:connection_id])
          send_object_data({ action: :config, cores: @cores })
        when :test
          test_case = object[:test_case]
          @process_manager.run_test_case(test_case)
        else
          Logger.error "Do not know how to process: #{obj}"
        end
      end

      def send_object_data(object)
        @connection.send_object(object)
      end
    end
  end
end
