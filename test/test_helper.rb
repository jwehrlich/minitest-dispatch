# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "minitest/dispatch"
require "minitest/autorun"
require "securerandom"
require "tempfile"

def new_test_file(class_name)
  file_name = class_name.gsub(/(.)([A-Z])/, '\1_\2').downcase
  file = Tempfile.open("test/unit/#{file_name}.rb")
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
