# frozen_string_literal: true

module Minitest
  module Dispatch
    class Settings
      DEFAULT_PORT = 33_333
      DEFAULT_HOST = "0.0.0.0"
      DEFAULT_CONSUMER = "#{DEFAULT_HOST}:#{DEFAULT_PORT}"
      DEFAULT_TEST_PATH = "test"
      DEFAULT_TIMEOUT = 60
      DEFAULT_INTERVAL = 1

      class << self
        def disable_autorun_tests
          Logger.debug "Disabling autorun of tests"
          ::Minitest.send(:define_singleton_method, :autorun) do
            Minitest::Dispatch::Logger.debug "`Minitest.autorun` has been disabled."
          end
        end

        def default_consumer_settings(additional_settings)
          shared_settings.merge(
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
            junit_report_path: "#{Dir.pwd}/test_results/junit_report.xml"
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
            workspace: Dir.pwd
          }
        end
      end
    end
  end
end
