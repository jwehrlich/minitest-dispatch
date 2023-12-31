# frozen_string_literal: true

require "test_helper"

module Minitest
  class VersionTest < Minitest::Test
    def test_that_it_has_a_version_number
      refute_nil ::Minitest::Dispatch::VERSION
    end
  end
end
