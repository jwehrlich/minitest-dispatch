module Minitest
  module Dispatch
    module Test
      # Stores test result data
      class Result
        attr_reader :assertions, :display, :errors, :failures, :location, :result_code, :run_count,
                    :source_location, :test_case, :test_suite, :time

        def initialize(test_case:, minitest_results:)
          @assertions = minitest_results.assertions
          @display = minitest_results.display
          @errors = []
          @failures = []
          @passed_bool = minitest_results.passed?
          @location = minitest_results.location
          @result_code = minitest_results.result_code
          @run_count = 1
          @skipped_bool = minitest_results.skipped?
          @test_case = test_case.kase
          @test_suite = test_case.klass
          @time = minitest_results.time.to_f
          @source_location = if minitest_results.respond_to?(:source_location)
                               minitest_results.source_location
                             else
                               [test_case.file, ""]
                             end

          process_minitest_failures(minitest_results.failures)
        end

        def error?
          errors.count.positive?
        end

        def failure?
          failures.count.positive?
        end

        def skipped?
          !!@skipped_bool
        end

        def passed?
          !!@passed_bool
        end

        private

        def process_minitest_failures(mt_failures)
          mt_failures.each do |mt_failure|
            formated_failure = formated_minitest_failure(mt_failure)
            case mt_failure
            when ::Minitest::Skip
              # Skip
            when ::Minitest::UnexpectedError
              @errors << formated_failure
            else
              @failures << formated_failure
            end
          end
        end

        def formated_minitest_failure(mt_failure)
          {
            class: mt_failure.class,
            exception: mt_failure.to_s,
            message: "Error:\n#{@test_suite}##{@test_case}\n#{mt_failure.message}"
          }
        end
      end
    end
  end
end
