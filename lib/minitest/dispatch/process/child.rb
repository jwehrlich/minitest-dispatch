require "eventmachine"

module Minitest
  module Dispatch
    module Process
      class Child
        include CallbacksMixin
        attr_reader :pid, :environment, :status, :current_test_case

        def initialize(environment)
          @semaphore = Thread::Mutex.new
          @status = :ready
          @parent_pid = ::Process.pid
          Logger.info "Parent PID for environment #{environment}: #{@parent_pid}"

          @environment = environment
          @current_test_case = nil

          start_forked_process

          EventMachine.add_periodic_timer(Settings::DEFAULT_INTERVAL) do
            begin
              next if @pid.nil?

              ::Process.getpgid(@pid) unless @current_test_case.nil?
            rescue Errno::ESRCH
              EventMachine.stop_event_loop
              log("Child's forked process failed", level: :debug)
              test_case = @current_test_case
              @current_test_case = nil
              trigger_callback(:recreate_child, self)
            end
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
            Signal.trap("SIGUSR1") {}
            Signal.trap("SIGCHLD") {}
            Signal.trap("USR1")    {}
            Signal.trap("EXIT")    {}
            @channel_to_child.receive_object do |object|
              run_test_case(object)
            end
          end

          log("Child PID for environment #{@environment}: #{@pid}")
          ::Process.detach(pid)
        end

        def scheduled_test_case(test_case)
          @semaphore.synchronize do
            if @status == :ready
              @status = :busy
              @current_test_case = test_case
              @channel_to_child.send_object(test_case)
            else
              Log("Child is busy, rescheduling test case for later: #{test_case}")
              trigger_callback(:failed_to_process, {test_case: test_case})
            end
          end
        end

        def busy?
          @status == :busy
        end

        def close_connections
          clear_callbacks
          @channel_to_child.close_connection
          @channel_to_parent.close_connection
        end

        def kill_process
          log("Killing #{self}, running: #{@current_test_case}", level: :debug)
          unless @current_test_case.nil?
            test_case = @current_test_case
            @current_test_case = nil
            trigger_callback(:failed_to_process, {test_case: test_case, options: {bad_core: true}})
          end

          begin
            return if @pid.nil?

            ::Process.getpgid(@pid) # will threw exception if not exist
            log("Killing child process #{@pid}...", level: :debug)
            ::Process.kill("USR1", @pid)
            @pid = nil
          rescue Errno::ESRCH
            # Process already killed
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
