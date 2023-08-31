require "eventmachine"

module Minitest
  module Dispatch
    module Connection
      # This is the general Connection type used for this service
      class Deferred < EventMachine::Connection
        include EventMachine::P::ObjectProtocol
        include CallbacksMixin

        attr_reader :id

        def initialize(*args)
          super
          obj = args.find { |arg| arg.key?(:connection_id) }
          @id = obj&.dig(:connection_id)
        end

        # If connection failed here because of Errno::ECONNREFUSED, than
        # no callbacks (post_inited and others) are set yet!
        # So we can't call post_inited here.
        # We need to call it on the next level of the dicision: connection_completed || unbind.
        # Also post_inited should be called only once.
        # So if it was called in connection_completed it should not be called in
        # unbind and vice versa.
        def post_init; end

        # This is never called when connection failed to be established.
        def connection_completed
          trigger_callback(:post_init, self)
          trigger_callback(:connect, self)
          trigger_callback(:connection_completed, self)
        end

        def send_object(object)
          super(object.merge(connection_id: @id))
        end

        def receive_object(data)
          trigger_callback(:receive_object, data)
        end

        def unbind(*)
          trigger_callback(:post_init, self)
          trigger_callback(:unbind, self)
        end

        def post_inited(&block)
          return if block.nil?

          @post_inited = proc do
            unless already_inited?
              block.call # Called only once for this object.
              already_inited!
            end
          end
        end
      end
    end
  end
end
