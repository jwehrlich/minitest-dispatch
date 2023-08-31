require "eventmachine"

module Minitest
  module Dispatch
    module Connection
      # This extends Deferred such that unbind will not be called.
      class Unbound < Deferred
        def unbind(*)
          trigger_callback(:post_init, self)
        end
      end
    end
  end
end
