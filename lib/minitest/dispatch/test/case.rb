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
          load_test_file_if_needed

          Logger.debug "Running #{@klass}.#{kase}..."
          mtest = Object.const_get(klass).new(kase)

          mtest.run
          mtest.failures = truncate_failures(mtest.failures)
          build_result(mtest)
        rescue Exception => e
          build_error_result(mtest, e)
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

        private

        def load_test_file_if_needed
          load file if !Object.const_defined?(klass) || Minitest::Dispatch::Settings::DEFAULT_AUTORELOAD
        end

        def truncate_failures(failures)
          failures.collect { |failure| truncate_failure(failure) }
        end

        def build_result(minitest_results)
          Result.new(
            test_case: self,
            minitest_results: minitest_results
          )
        end

        def build_error_result(mtest, error)
          result = convert_to_minitest_result(mtest)
          append_normalized_failures(result, failure_candidates(mtest, error), error)
          build_result(result)
        end

        def convert_to_minitest_result(mtest)
          return mtest unless defined?(::Minitest::Result)

          result = ::Minitest::Result.from(mtest)
          result.assertions = 0
          result.time = 0.0
          result
        end

        def failure_candidates(mtest, error)
          if mtest.respond_to?(:failures) && mtest.failures.any?
            Array(mtest.failures).flatten
          else
            [error]
          end
        end

        def append_normalized_failures(result, failures, fallback_error)
          return unless result.respond_to?(:failures) && result.failures.respond_to?(:<<)

          failures.each do |failure|
            result.failures << normalize_failure(failure, fallback_error: fallback_error)
          end
        end

        # Safely truncates long failure messages while preserving exception metadata.
        # Truncation prevents marshalling errors when transmitting results over IPC and
        # ensures consistent output formatting in reports.
        #
        # Special handling for Minitest::UnexpectedError:
        #   - Wraps the truncated message in a new StandardError
        #   - Extracts backtrace from the nested exception (failure.exception.backtrace)
        #   - Returns new UnexpectedError wrapper to maintain exception type
        #   - This preserves the distinction between assertion failures and unexpected errors
        #
        # For assertion failures and other exceptions:
        #   - Creates new instance of failure.class with truncated message
        #   - Transfers original backtrace via set_backtrace
        #   - Falls back to StandardError if truncated instance creation fails (rescue clause)
        #
        # @param failure [Exception] the failure/error to potentially truncate
        # @return [Exception] original failure if within size limit, or truncated wrapper
        def truncate_failure(failure)
          truncated_message = truncated_message_for(failure)
          return failure if truncated_message.nil?

          return truncate_unexpected_error(failure, truncated_message) if unexpected_error_failure?(failure)

          build_truncated_failure(failure, truncated_message)
        rescue StandardError
          # Fallback when failure.class.new(msg) fails (e.g., custom exception with required args)
          fallback_message = truncated_message || failure.to_s
          fallback = StandardError.new(fallback_message)
          fallback.set_backtrace(safe_backtrace_for(failure))
          fallback
        end

        def truncated_message_for(failure)
          message = failure.respond_to?(:message) ? failure.message.to_s : failure.to_s
          return if message.length <= @max_message_size

          "[TRUNCATED] #{message[0..@max_message_size]}..."
        end

        def unexpected_error_failure?(failure)
          defined?(::Minitest::UnexpectedError) && failure.is_a?(::Minitest::UnexpectedError)
        end

        def truncate_unexpected_error(failure, truncated_message)
          exception = StandardError.new(truncated_message)
          source = failure.exception
          source_backtrace = source.respond_to?(:backtrace) ? source.backtrace : []
          exception.set_backtrace(source_backtrace || [])
          ::Minitest::UnexpectedError.new(exception)
        end

        def build_truncated_failure(failure, truncated_message)
          truncated_failure = failure.class.new(truncated_message)
          return truncated_failure unless truncated_failure.respond_to?(:set_backtrace)

          truncated_failure.set_backtrace(safe_backtrace_for(failure))
          truncated_failure
        end

        def safe_backtrace_for(failure)
          backtrace = failure.respond_to?(:backtrace) ? failure.backtrace : []
          backtrace || []
        end

        # Converts non-exception objects to proper Exception instances.
        # The rescue path in #run may yield non-standard failures (strings, custom objects).
        # This ensures all items in result.failures have a backtrace method for minitest
        # compatibility and prevents "undefined method backtrace for String" errors.
        #
        # @param failure [Object] any failure object
        # @param fallback_error [Exception] the original caught exception; used for backtrace if failure lacks one
        # @return [Exception] a StandardError wrapping the failure if needed, or the original failure
        def normalize_failure(failure, fallback_error:)
          return failure if failure.respond_to?(:backtrace)

          normalized = StandardError.new(failure.to_s)
          normalized.set_backtrace(fallback_error&.backtrace || [])
          normalized
        end
      end
    end
  end
end
