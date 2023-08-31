module Minitest
  module Dispatch
    module Process
      # This manages a collection of child processes. (ie: test runners).
      class Manager
        include CallbacksMixin

        def initialize(cores:, core_offset: Settings::DEFAULT_CORE_OFFSET)
          @semaphore = Thread::Mutex.new
          @cores = cores
          @core_offset = core_offset
          @children = []
          @c_pos = 0
        end

        def start
          (@core_offset...(@core_offset + @cores)).each do |environment|
            @children << create_child(environment)
          end
        end

        def create_child(environment)
          child = Child.new(environment)
          child.add_callback(:failed_to_process) { |object| trigger_callback(:failed_to_process, object) }
          child.add_callback(:test_finished)     { |result| trigger_callback(:test_finished, result) }

          child.add_callback(:recreate_child) do |old_child|
            old_child.kill_process

            Logger.debug "Recreating child: #{old_child}"
            index = @children.find_index { |c| c.environment == old_child.environment }

            @children[index] = create_child(old_child.environment)
            Logger.debug "Created new child: #{@children[index]}"
          end
        end

        def run_test_case(test_case)
          @semaphore.synchronize do
            child = @children.find { |c| !c.busy? }

            if child.nil?
              Logger.error "Cannot run test right now, rescheduling test to be re-ran"
              trigger_callback(:failed_to_process, { test_case: test_case })
            else
              child.scheduled_test_case(test_case)
            end
          end
        end

        def stop
          @semaphore.synchronize do
            return if defined? @shutdown

            @shutdown = true
            Logger.debug "Stopping all #{@children.size} children..."
            @children.each(&:kill_process)
          end
        end
      end
    end
  end
end
