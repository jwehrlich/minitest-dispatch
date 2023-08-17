require "eventmachine"

module Minitest
  module Dispatch
    module Connection
      class Deferred < EventMachine::Connection
        include EventMachine::P::ObjectProtocol
        include CallbacksMixin

        def initialize(*args)
          super
          obj = args.find { |arg| arg.key?(:connection_id) }
          @connection_id = obj[:connection_id] unless obj.nil?
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
          super(object.merge(connection_id: @connection_id))
        end

        def receive_object(data)
          trigger_callback(:receive_object, data)
        end

        def unbind(reason)
          trigger_callback(:post_init, self)
          trigger_callback(:unbind, error? || reason)
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
