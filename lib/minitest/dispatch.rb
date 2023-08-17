require "minitest"

Dir["#{__dir__}/dispatch/**/*.rb"].sort.each { |file| require_relative file }

module Minitest
  module Dispatch
  end
end
