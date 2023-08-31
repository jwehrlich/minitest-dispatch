require "minitest"

Dir["#{__dir__}/dispatch/**/*.rb"].sort.each { |file| require_relative file }

module Minitest
  # Dispatch module definition
  module Dispatch
  end
end
