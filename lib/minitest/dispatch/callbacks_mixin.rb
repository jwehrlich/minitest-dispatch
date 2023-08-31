module Minitest
  module Dispatch
    # This is basically and Observer pattern in which sources can register for a notification at some
    # point in the future
    module CallbacksMixin
      def add_callback(name, &block)
        original_name = name
        name = "#{name}_callback" unless /^.*_callback$/.match(name)
        Logger.debug "[#{self.class}] Callback added for: #{original_name}"

        @callbacks_collection ||= {}
        @callbacks_collection[name] ||= Set.new
        @callbacks_collection[name] << block
        self
      end

      def trigger_callback(name, object)
        name = "#{name}_callback" unless /^.*_callback$/.match(name)

        @callbacks_collection ||= {}
        @callbacks_collection[name] ||= Set.new
        @callbacks_collection[name].each do |callback|
          callback.call(object)
        end
      end

      def clear_callbacks
        Logger.debug "Clearing callbacks: #{@callbacks_collection}"
        @callbacks_collection = {}
      end
    end
  end
end
