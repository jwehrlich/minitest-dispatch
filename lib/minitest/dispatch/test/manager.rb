# frozen_string_literal: true

require "pathname"

module Minitest
  module Dispatch
    module Test
      # Manages a collection of test cases
      class Manager
        class NoSuchFile < RuntimeError; end

        FILE_PATTERN = /^.*_test\.rb$/.freeze
        TEST_PATTERN = /^test_.*/.freeze

        attr_reader :test_cases, :test_results

        def initialize(test_files, retries_allowed: nil, total_retries_allowed: nil)
          @semaphore = Thread::Mutex.new
          @test_cases = []
          @test_results = { test_count: 0 }
          @retries_allowed = retries_allowed || Settings::DEFAULT_RETRY_COUNT
          @total_retries_allowed = total_retries_allowed || Settings::DEFAULT_TOTAL_RETRIES
          @total_retries = 0
          load_test_files(test_files)
          load_test_cases
        end

        def load_test_files(test_files)
          Logger.info "Loading test files..."
          items = test_files.split(",")

          files = []
          items.each do |item|
            absolute_path = Pathname.new(item).realpath
            if File.directory?(absolute_path)
              Dir.glob("#{item}/**/*_test.rb").each do |sub_item|
                next if File.directory?(sub_item)

                files << Pathname.new(sub_item).realpath
              end
            else
              files << absolute_path
            end
          rescue Errno::ENOENT
            raise NoSuchFile, "No such file or folder: #{item}"
          end

          files.uniq.each do |item|
            require item if file_match?(item)
          end
        end

        def load_test_cases
          Logger.info "Loading test cases..."
          ObjectSpace.each_object(Minitest::Test.singleton_class).each do |test_class|
            # TODO: We need to figure out what happens if two files are loaded with the same class but different tests
            get_class_details(test_class).each do |test_file|
              test_class.instance_methods(false).select { |m| TEST_PATTERN.match?(m.to_s) }.sort.each do |test_case|
                @test_cases << Test::Case.new(
                  file: test_file,
                  klass: test_class,
                  kase: test_case,
                  retries: @retries_allowed
                )
              end
            end
          end
        end

        def get_class_details(klass)
          @class_details ||= {}
          return @class_details[klass] unless @class_details[klass].nil?

          @class_details[klass] = Set.new
          klass.instance_methods(false).sort.each do |m|
            if TEST_PATTERN.match?(m.to_s)
              test_path = klass.instance_method(m).source_location.first
              @class_details[klass].add(test_path) if file_match?(test_path)
            end
          end
          @class_details[klass]
        end

        def file_match?(file_path)
          base_name = File.basename(file_path)
          File.file?(file_path) && FILE_PATTERN.match(base_name)
        end

        def add_result(result)
          @semaphore.synchronize do
            suite = result.test_suite
            @test_results[:test_count] += 1
            @test_results[suite] ||= {
              assertions: 0,
              errors: 0,
              failures: 0,
              filepath: result.source_location[0],
              skipped: 0,
              test_results: [],
              tests: 0,
              time: 0.0
            }

            @test_results[suite][:assertions] += result.assertions
            @test_results[suite][:errors] += result.errors.count
            @test_results[suite][:failures] += result.failures.count
            @test_results[suite][:skipped] += result.skipped? ? 1 : 0
            @test_results[suite][:tests] += 1
            @test_results[suite][:time] += result.time
            @test_results[suite][:test_results] << result
          end
        end

        def update_status(test_class:, test_case:, status:, connection_id: nil)
          @semaphore.synchronize do
            index = @test_cases.find_index { |tc| tc.klass == test_class && tc.kase == test_case }
            if index.nil?
              Logger.error "Could not find test case in processing list: #{test_class}##{test_case}"
              return false
            end

            cur_case = @test_cases[index]

            if status == Test::Case::RETRY_OR_FINISH
              Logger.debug "#{test_class}##{test_case} : { retries: #{cur_case.retries}, " \
                           "retries_performed: #{@total_retries}, retries_allowed: #{@total_retries_allowed} }"

              if cur_case.retries.positive? && @total_retries <= @total_retries_allowed
                @total_retries += 1
                cur_case.retries -= 1
                cur_case.status = Test::Case::PENDING_STATUS
              else
                cur_case.status = Test::Case::FINISHED_STATUS
              end

            else
              cur_case.status = status
            end

            Logger.debug "#{test_class}##{test_case} : #{status}"
            cur_case.connection_id = connection_id
            return cur_case
          end
        end

        def next_batch(count)
          @semaphore.synchronize do
            batch = []
            @test_cases.each do |test_case|
              if test_case.pending?
                batch << test_case
                count -= 1
              end
              break unless count.positive?
            end
            batch
          end
        end

        def tests_for(connection_id:)
          @semaphore.synchronize do
            @test_cases.select { |test_case| test_case.connection_id == connection_id }
          end
        end

        def running_tests
          @semaphore.synchronize do
            @test_cases.select(&:running?)
          end
        end

        def running?
          !finished?
        end

        def finished?
          @semaphore.synchronize do
            @test_results[:test_count] >= @test_cases.count
          end
        end
      end
    end
  end
end
