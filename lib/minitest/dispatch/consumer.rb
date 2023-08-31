require "eventmachine"

module Minitest
  module Dispatch
    # This is the main entry point for the consumer server. This will connect to a manager
    # that will instruct with test should be executed next for the consumer instance
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
        @core_offset = options[:core_offset]
        @host = options[:host]
        @port = options[:port]

        @process_manager = Process::Manager.new(cores: @cores, core_offset: @core_offset)
        @process_manager.add_callback(:failed_to_process) do |object|
          obj = {
            action: :reschedule_test,
            test_case: object[:test_case],
            options: object[:options]
          }
          send_object_data(obj)
        end
        @process_manager.add_callback(:test_finished) do |result|
          send_object_data({ action: :test_result, result: result })
        end
      end

      def run
        Signal.trap("SIGINT") do
          Settings.set_in_trap
          @process_manager.stop
          @connection&.close_connection_after_writing
          EventMachine.stop_event_loop
        end

        Signal.trap("EXIT") do
          Settings.set_in_trap
          @process_manager.stop
          @connection&.close_connection_after_writing
          EventMachine.stop_event_loop
        end

        EventMachine.run do
          Logger.info "Start event machine server: #{@host}:#{@port}"
          @process_manager.start

          EventMachine.start_server(@host, @port.to_i, Connection::Deferred) do |connection|
            old_connection = @connection
            @connection = connection

            msg_prefix = if old_connection.nil?
                           "Established"
                         else
                           @connection.instance_variable_set(:@id, old_connection.id)
                           old_connection.clear_callbacks
                           "Refreshed"
                         end

            Logger.info "#{msg_prefix} connection with manager established: #{@connection.inspect}"

            @connection.add_callback(:post_init) {} # TODO: post_init callback
            @connection.add_callback(:receive_object) do |object|
              process_object(object)
            end

            @connection.add_callback(:unbind) do
              EventMachine::Timer.new(Settings::DEFAULT_INTERVAL) do
                @connection.reconnect(@host, @port.to_i)
              end
            end
          end
        end
      end

      def process_object(object)
        case object[:action]
        when :config
          # Send the details regarding processing availability for node
          Logger.info "Config request: #{object}"
          @connection.instance_variable_set(:@id, object[:connection_id])
          send_object_data({ action: :config, cores: @cores })
        when :test
          test_case = object[:test_case]
          @process_manager.run_test_case(test_case)
        when :disconnect
          @process_manager.stop
          @connection&.close_connection_after_writing
          EventMachine.stop_event_loop
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
