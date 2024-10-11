# frozen_string_literal: true

module Minitest
  module Dispatch
    # This is a global settings object that can be used to store data that should be
    # stored across the application
    class Settings
      DEFAULT_PORT ||= 33_333
      DEFAULT_HOST ||= "0.0.0.0"
      DEFAULT_CONSUMER ||= "#{DEFAULT_HOST}:#{DEFAULT_PORT}"
      DEFAULT_CORE_OFFSET ||= 0
      DEFAULT_TEST_PATH ||= "test"
      DEFAULT_TIMEOUT ||= 60
      DEFAULT_INTERVAL ||= 1
      DEFAULT_RETRY_COUNT ||= 0
      DEFAULT_TOTAL_RETRIES ||= 0
      DEFAULT_AUTORELOAD ||= false
      DEFAULT_MAX_FAILURE_MESSAGE_SIZE ||= 7_000

      class << self
        attr_reader :in_trap

        def set_in_trap
          @in_trap = true
        end

        def disable_autorun_tests
          Logger.debug "Disabling autorun of tests"
          ::Minitest.send(:define_singleton_method, :autorun) do
            Minitest::Dispatch::Logger.debug "`Minitest.autorun` has been disabled."
          end
        end

        def default_consumer_settings(additional_settings)
          shared_settings.merge(
            core_offset: DEFAULT_CORE_OFFSET,
            cores: Etc.nprocessors,
            host: DEFAULT_HOST,
            port: DEFAULT_PORT
          ).merge(additional_settings).tap do |ret|
            $LOAD_PATH.unshift File.expand_path(ret[:load_path])
          end
        end

        def default_manager_settings(additional_settings)
          shared_settings.merge(
            consumers: DEFAULT_CONSUMER,
            junit_report_path: "#{Dir.pwd}/test_results/junit_report.xml",
            junit_test_class_prefix: ""
          ).merge(additional_settings).tap do |ret|
            $LOAD_PATH.unshift File.expand_path(ret[:load_path])
          end
        end

        private

        def shared_settings
          {
            load_path: DEFAULT_TEST_PATH,
            mode: nil,
            test_files: DEFAULT_TEST_PATH,
            timeout: DEFAULT_TIMEOUT,
            workspace: Dir.pwd,
            autoreload: DEFAULT_AUTORELOAD
          }
        end
      end
    end
  end
end
