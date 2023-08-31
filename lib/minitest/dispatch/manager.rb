require "eventmachine"

module Minitest
  module Dispatch
    # This is the main entry point for the central server that will manager the Orchestration
    # of test runs and report generation.
    class Manager
      def self.start(options)
        Logger.info "Starting manager..."
        Settings.disable_autorun_tests
        @instance ||= new(options)
        @instance.run
      end

      def initialize(options)
        @application_start_time = Time.now

        unless (@workspace = options[:workspace]) && File.directory?(@workspace)
          raise "Workspace provided is not a valid dictory: #{@workspace}"
        end

        @connection_manager = Connection::Manager.new(consumers: options[:consumers], timeout: options[:timeout])
        @connection_manager.add_callback(:receive_object) do |object|
          process_object(object)
        end

        @test_files = options[:test_files]
        @test_manager = Test::Manager.new(@test_files)

        @junit_test_class_prefix = options[:junit_test_class_prefix]
        @junit_report_path = options[:junit_report_path]
      end

      def run
        EventMachine.run do
          @healthcheck = EventMachine.add_periodic_timer(Settings::DEFAULT_INTERVAL) do
            Logger.debug "Processed: #{@test_manager.test_results[:test_count]} of #{@test_manager.test_cases.count}"
            # Logger.debug "Active tests:\n#{@test_manager.running_tests.join("\n")}"
            @connection_manager.close_all if @test_manager.finished?
          end

          @connection_manager.add_callback(:unbind) do |connection|
            if @test_manager.running?
              EventMachine::Timer.new(Settings::DEFAULT_INTERVAL) do
                adapter = @connection_manager.adapter_for(connection_id: connection.id)
                @test_manager.tests_for(connection_id: adapter.connection_id).each do |test_case|
                  @test_manager.update_status(
                    test_class: test_case.klass,
                    test_case: test_case.kase,
                    status: Test::Case::PENDING_STATUS
                  )
                end
                begin
                  adapter.reconnect
                rescue Connection::Adapter::TooManyRetryAttpempts
                  shutdown(failed_message: "Lost connections to consumers") if @connection_manager.disconnected?
                end
              end
            else
              shutdown
            end
          end
          @connection_manager.open_all
        end
      end

      def shutdown(failed_message: nil)
        return if @shutdown

        @shutdown = true
        @healthcheck.cancel
        @connection_manager.clear_callbacks
        @connection_manager.close_all

        if failed_message.nil?
          JUnitReport.generate(
            report_path: @junit_report_path,
            test_results: @test_manager.test_results,
            class_prefix: @junit_test_class_prefix
          )
          print_result_summary(@test_manager.test_results)
        else
          Logger.error failed_message
        end

        EventMachine.stop_event_loop
      end

      def process_object(object)
        case object[:action]
        when :config
          Logger.info "Cores for #{object[:connection_id]}: #{object[:cores]}"
          @connection_manager.adapter_for(connection_id: object[:connection_id])
                             .instance_variable_set(:@cores, object[:cores])
          process_test_batch(connection_id: object[:connection_id], count: object[:cores])
        when :test_result
          result = object[:result]
          print result.result_code
          @test_manager.update_status(
            test_class: result.test_suite,
            test_case: result.test_case,
            status: Test::Case::FINISHED_STATUS
          )
          @test_manager.add_result(result)
          conn_adapter = @connection_manager.adapter_for(connection_id: object[:connection_id])
          process_test_batch(connection_id: conn_adapter.connection_id, count: 1)
        when :reschedule_test
          test_case = object[:test_case]
          Logger.info "Rescheduling test: #{test_case.klass}##{test_case.kase}"
          @test_manager.update_status(
            test_class: test_case.klass,
            test_case: test_case.kase,
            status: Test::Case::PENDING_STATUS
          )

          unless object.dig(:options, :bad_core)
            EventMachine::Timer.new(Settings::DEFAULT_INTERVAL) do
              conn_adapter = @connection_manager.adapter_for(connection_id: object[:connection_id])
              process_test_batch(connection_id: conn_adapter.connection_id, count: 1)
            end
          end
        else
          Logger.error "Unexpected action `#{object[:action]}` : #{object}"
        end
      end

      def process_test_batch(connection_id:, count:)
        conn_adapter = @connection_manager.adapter_for(connection_id: connection_id)
        if conn_adapter.connection
          batch = @test_manager.next_batch(count)
          batch.each do |test_case|
            @test_manager.update_status(
              test_class: test_case.klass,
              test_case: test_case.kase,
              status: Test::Case::RUNNING_STATUS,
              connection_id: connection_id
            )
            conn_adapter.connection.send_object({ test_case: test_case, action: :test })
          end
        else
          Logger.info "Connection to #{connection_id} is closed."
        end
      end

      private

      def print_result_summary(test_results)
        summary = { assertions: 0, errors: 0, failures: 0, skipped: 0, tests: 0, time: 0.0 }

        test_results.each do |suite_name, suite_results|
          summary[:assertions] += suite_results[:assertions]
          summary[:errors] += suite_results[:errors]
          summary[:failures] += suite_results[:failures]
          summary[:skipped] += suite_results[:skipped]
          summary[:tests] += suite_results[:tests]
          summary[:time] += suite_results[:time]
          print_results(label: suite_name, results: suite_results)
        end

        print_results(label: "all test suites", results: summary)
        puts format("\nActual running time was: %<time>.5fs", time: Time.now - @application_start_time)
      end

      def print_results(label:, results:)
        finished_message = format("Finished %<label>s in %<time>.5fs.", label: label, time: results[:time])
        line = "-" * finished_message.length
        puts "\n\n#{line}\n#{finished_message}\n#{line}\n\n"

        failure_count = 0
        (results[:test_results] || []).each do |test_result|
          (test_result.failures + test_result.errors).each do |failure|
            failure_count += 1
            puts "#{failure_count}) #{failure[:message]}\n\n"
          end
        end

        puts "#{results[:tests]} runs, #{results[:assertions]} assertions, " \
             "#{results[:failures]} failures, #{results[:errors]} errors, #{results[:skipped]} skips"
      end
    end
  end
end
