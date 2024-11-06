# frozen_string_literal: true

module Minitest
  module Dispatch
    module Test
      # This is a specific test case for a given test suite
      class Case
        PENDING_STATUS = "pending"
        RUNNING_STATUS = "running"
        FINISHED_STATUS = "finished"
        RETRY_OR_FINISH = "retry_or_finish"

        attr_accessor :status, :retries, :connection_id
        attr_reader :file, :klass, :kase

        def initialize(file:, klass:, kase:, retries: Settings::DEFAULT_RETRY_COUNT)
          @file = file
          @klass = klass.name
          @kase = kase
          @status = PENDING_STATUS
          @retries = retries
          @max_message_size = Settings::DEFAULT_MAX_FAILURE_MESSAGE_SIZE
        end

        def run
          load file if !Object.const_defined?(klass) || Minitest::Dispatch::Settings::DEFAULT_AUTORELOAD

          Logger.debug "Running #{@klass}.#{kase}..."
          mtest = Object.const_get(klass).new(kase)

          mtest.run
          mtest.failures = mtest.failures.collect do |failure|
            if (message = failure.message).length > @max_message_size
              f = failure.class.new("[TRUNCATED] #{message[0..@max_message_size]}...")
              f.set_backtrace(failure.backtrace)
              f
            else
              failure
            end
          end

          Result.new(
            test_case: self,
            minitest_results: mtest
          )
        rescue Exception => e
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

        def finished?
          @status == FINISHED_STATUS
        end

        def to_s
          "[\"#{@file}\", \"#{@klass}\", \"#{@kase}\", \"#{@status}]"
        end
      end
    end
  end
end
