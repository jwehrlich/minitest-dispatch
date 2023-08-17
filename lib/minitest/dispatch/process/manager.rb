module Minitest
  module Dispatch
    module Process
      class Manager
        include CallbacksMixin

        def initialize(cores:)
          @semaphore = Thread::Mutex.new
          @cores = cores
          @children = []
          @c_pos = 0
        end

        def start
          @cores.times do |environment|
            @children << create_child(environment)
          end
        end

        def create_child(environment)
          child = Child.new(environment)
          child.add_callback(:failed_to_process) { |object| trigger_callback(:failed_to_process, object) }
          child.add_callback(:test_finished)     { |result| trigger_callback(:test_finished, result) }

          child.add_callback(:recreate_child) do |child|
            test_case = child.current_test_case
            child.close_connections

            Logger.debug "Deleting child: #{child}"
            @children.delete_if do |c|
              c.pid == child.pid && c.environment && child.environment
            end

            child = create_child(environment)
            Logger.debug "Created new child: #{child}"
            child.scheduled_test_case(test_case) unless test_case.nil?
            @children << child
          end
        end

        def run_test_case(test_case)
          @semaphore.synchronize do
            child = @children.find { |c| !c.busy? }

            if child.nil?
              Logger.error "Cannot run test right now, rescheduling test to be re-ran"
              trigger_callback(:failed_to_process, {test_case: test_case})
            else
              child.scheduled_test_case(test_case)
            end
          end
        end

        def stop(is_trap: false)
          Logger.debug "Stopping all #{@children.size} children..." unless is_trap
          @children.each(&:kill_process)
        end
      end
    end
  end
end
