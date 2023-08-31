module Minitest
  module Dispatch
    module Connection
      # This creates a communication tunnel between forked processes and the parent task.
      class Channel
        include CallbacksMixin

        def initialize
          @io_read, @io_write = IO.pipe
        end

        def receive_data(&block)
          add_callback(:receive_data, &block)
        end

        def receive_object(&block)
          setup_read
          add_callback(:receive_object, &block)
        end

        def send_data(data)
          write.send_data(data)
        end

        def send_object(object)
          send_data(Marshal.dump(object))
        end

        def close_connections
          @read.close_connection_after_writing if defined? @read
          @write.close_connection_after_writing if defined? @write
        end

        private

        def setup_read
          @read ||= EventMachine.attach(@io_read, Unbound)

          me = self
          @read.define_singleton_method :receive_data do |data|
            me.trigger_callback(:receive_data, data)
            me.trigger_callback(:receive_object, Marshal.load(data))
          end
        end

        def write
          @write ||= EventMachine.attach(@io_write)
        end
      end
    end
  end
end
