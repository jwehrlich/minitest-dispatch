require "eventmachine"

module Minitest
  module Dispatch
    module Process
      # This is manages a forked process that can run tests.
      class Child
        include CallbacksMixin
        attr_accessor :current_test_case
        attr_reader :pid, :environment, :status

        def initialize(environment)
          @semaphore = Thread::Mutex.new
          @status = :ready
          @parent_pid = ::Process.pid
          Logger.info "Parent PID for environment #{environment}: #{@parent_pid}"

          @environment = environment
          @current_test_case = nil

          start_forked_process

          @healthcheck = EventMachine::PeriodicTimer.new(Settings::DEFAULT_INTERVAL) do
            ::Process.getpgid(@pid)
          rescue Errno::ESRCH
            log("Child's forked process failed", level: :debug)
            @healthcheck.cancel
            trigger_callback(:recreate_child, self)
          end
        end

        def start_forked_process
          @channel_to_child = ::Minitest::Dispatch::Connection::Channel.new
          @channel_to_parent = ::Minitest::Dispatch::Connection::Channel.new
          @channel_to_parent.receive_object do |object|
            @status = :ready
            @current_test_case = nil
            trigger_callback(:test_finished, object)
          end

          @pid = EventMachine.fork_reactor do
            @pid = ::Process.pid # inside fork, does not know about outsite @pid
            @channel_to_child.receive_object do |object|
              run_test_case(object)
            end
          end

          log("Child PID for environment #{@environment}: #{@pid}")
          ::Process.detach(@pid)
        end

        def scheduled_test_case(test_case)
          @semaphore.synchronize do
            if @status == :ready
              @status = :busy
              @current_test_case = test_case
              @channel_to_child.send_object(test_case)
            else
              Log("Child is busy, rescheduling test case for later: #{test_case}")
              trigger_callback(:failed_to_process, { test_case: test_case })
            end
          end
        end

        def busy?
          @status == :busy
        end

        def close_connections
          clear_callbacks
          @channel_to_child.close_connections
          @channel_to_parent.close_connections
        end

        def kill_process
          @status = :busy
          log("Killing #{self}, running: #{@current_test_case}", level: :debug)

          unless @current_test_case.nil?
            object = { test_case: @current_test_case, options: { bad_core: true } }
            trigger_callback(:failed_to_process, object)
          end

          begin
            close_connections
            ::Process.getpgid(@pid) # will threw exception if not exist
            log("Killing child process #{@pid}...", level: :debug)
            ::Process.kill("USR1", @pid)
          rescue Errno::ESRCH
            # Process already killed
          ensure
            @pid = nil
          end
        end

        def to_s
          "#<Child pid: #{@pid}, parent_pid: #{@parent_pid}, environment: #{@environment}>"
        end

        private

        def log(msg, level: :info)
          Logger.send(level.to_sym, "[#{@parent_pid}.#{@pid}.#{@environment}] [#{::Process.pid}] #{msg}")
        end

        def run_test_case(test_case)
          log("Running test case: #{test_case}")
          orig_env = ENV.fetch("TEST_ENV_NUMBER", nil)
          ENV["TEST_ENV_NUMBER"] = @environment.to_s

          begin
            result = test_case.run
          ensure
            ENV["TEST_ENV_NUMBER"] = orig_env
          end

          @channel_to_parent.send_object(result)
        end
      end
    end
  end
end
