# frozen_string_literal: true

require "byebug"
require "minitest/unit"
require "mocha/minitest"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "minitest/dispatch"
require "minitest/autorun"
require "securerandom"
require "fileutils"
require "tempfile"

Minitest::Dispatch::Settings.const_set("DEFAULT_AUTORELOAD", true)
TMP_DIR_PATH = "test/tmp"

def new_test_file(class_name)
  FileUtils.mkdir_p(TMP_DIR_PATH)
  file_name = class_name.gsub(/(.)([A-Z])/, '\1_\2').downcase
  file = Tempfile.open([file_name, "_test.rb"], TMP_DIR_PATH)
  file.puts "require 'test_helper'"
  file.puts "class #{class_name} < Minitest::Test"
  file.puts yield
  file.puts "end"
  file.close
  file
end

def new_test_case(case_name)
  "def test_#{case_name}\n#{yield if block_given?}\nend"
end

def run_test(options)
  file_path = File.join(Dir.pwd, options[:file])
  @test_exception = nil
  @manager_port = 8201

  EventMachine.next_tick do
    consumer_options = {
      cores: 1,
      core_offset: 0,
      host: "localhost",
      port: @manager_port
    }
    @dispatch_consumer = Minitest::Dispatch::Consumer.new(consumer_options)
    @dispatch_consumer.run
  end

  @manager = Minitest::Dispatch::Manager.new({
                                               workspace: File.dirname(file_path),
                                               consumers: "localhost:#{@manager_port}",
                                               test_files: file_path,
                                               retries: options[:retries] || 0
                                             })
  test_manager = @manager.instance_variable_get("@test_manager")
  test_manager.test_cases.clear

  test_manager.test_cases << Minitest::Dispatch::Test::Case.new(
    file: file_path,
    klass: Object.const_get(options[:class_name]),
    kase: "test_#{options[:test_case]}",
    retries: options[:retries] || Minitest::Dispatch::Settings::DEFAULT_RETRY_COUNT
  )

  Minitest::Dispatch::Manager.any_instance.stubs(:shutdown).with do |*args|
    yield test_manager.test_results
  rescue Exception => e
    @test_exception = e
  ensure
    Minitest::Dispatch::Manager.any_instance.unstub(:shutdown)
    @manager.shutdown(*args, should_prompt: false)
    @dispatch_consumer.instance_variable_get("@process_manager").stop
  end

  begin
    @manager.run
  rescue Exception => e
    @test_exception = e
  end

  raise @test_exception if @test_exception
end
