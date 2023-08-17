# frozen_string_literal: true

module Minitest
  module Dispatch
    module Test
      class Case
        PENDING_STATUS = "pending"
        RUNNING_STATUS = "running"
        FINISHED_STATUS = "finished"

        attr_accessor :status
        attr_reader :file, :klass, :kase

        def initialize(file:, klass:, kase:)
          @file = file
          @klass = klass.name
          @kase = kase
          @status = PENDING_STATUS
        end

        def run
          require_relative file unless klass.is_a?(Class)

          Logger.debug "Running #{@klass}.#{kase}..."
          mtest = Object.const_get(klass).new(kase)

          Result.new(
            test_case: self,
            minitest_results: mtest.run
          )
        rescue RuntimeError => e
          result = mtest
          if defined?(::Minitest::Result)
            result = ::Minitest::Result.from(mtest)
            result.assertions = 0
            result.time = 0.0
          end
          result.failures << mtest.sanitize_exception(e)

          Result.new(
            test_case: self,
            minitest_results: result
          )
        end

        def pending?
          @status == PENDING_STATUS
        end

        def running?
          @status == RUNNING_STATUS
        end

        def to_s
          "#<TestCase file: '#{@file}', class: '#{@klass}', case: '#{@kase}', status: #{@status}>"
        end
      end
    end
  end
end
