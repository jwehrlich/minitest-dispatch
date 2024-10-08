require "test_helper"

class TestManagerTest < Minitest::Test
  def test_basic_test
    file = new_test_file("MyTestCase") do
      new_test_case("foo") do
        "puts foo"
      end
    end
    Minitest::Dispatch::Test::Manager.new(file.path)
  end

  def test_bad_test_file_path
    path = "test/unit/fake_test.rb"
    ex = assert_raises Minitest::Dispatch::Test::Manager::NoSuchFile do
      Minitest::Dispatch::Test::Manager.new(path)
    end
    assert_equal "No such file or folder: #{path}", ex.message
  end

  def test_truncated_failure
    class_name = "TruncatedTest"
    file = new_test_file(class_name) do
      new_test_case("case") do
        <<-VALIDATIONS
        arr_one = 10000.times.collect { (0...100).map { (65 + rand(26)).chr }.join }
        arr_two = 100.times.collect { (0...100).map { (65 + rand(26)).chr }.join }
        assert_equal arr_one, arr_two
        VALIDATIONS
      end
    end
    run_test({ file: file, class_name: class_name, test_case: "case" }) do |results|
      results = results[class_name]
      assert_equal 1, results[:tests], "expected only one test"
      assert_equal 0, results[:errors], "expected no error"
      assert_equal 1, results[:failures], "expected only one failure"
      assert_equal 1, results[:assertions], "expected only one assertion"
      assert_equal 0, results[:skipped], "expected no skips"
      assert results[:test_results].one?, "expected test results"
      test_result = results[:test_results].first

      assert !test_result.error?, "epected not to error"
      assert test_result.failure?, "epected a failure"
      assert !test_result.passed?, "expected not to pass"
      assert !test_result.skipped?, "expected not to skip"

      assert test_result.errors.none?
      assert test_result.failures.one?
      failure_msg = test_result.failures.first[:message]
      assert failure_msg.include?("TRUNCATED"), failure_msg
    end
  end

  def test_failed_assert
    file = new_test_file("MyTestCase") do
      new_test_case("foo") do
        "assert false, 'failed assertion'"
      end
    end
    Minitest::Dispatch::Test::Manager.new(file.path)
  end

  def test_exception_raised
    file = new_test_file("MyTestCase") do
      new_test_case("foo") do
        "raise 'this test should fail'"
      end
    end
    Minitest::Dispatch::Test::Manager.new(file.path)
  end

  def test_skipped
    file = new_test_file("MyTestCase") do
      new_test_case("foo") do
        "skip"
      end
    end
    Minitest::Dispatch::Test::Manager.new(file.path)
  end

  def test_duplicate_test_class
    file_a = new_test_file("MyTestCase") do
      new_test_case("foo") do
        "puts foo"
      end
    end

    file_b = new_test_file("MyTestCase") do
      new_test_case("foo") do
        "puts foo"
      end
    end
    Minitest::Dispatch::Test::Manager.new("#{file_a.path},#{file_b.path}")
  end

  def test_io_error
    class_name = "IntegrationTestsOne"
    test_case = "foo"
    file = new_test_file(class_name) do
      new_test_case(test_case) do
        "$stdout.fake('something')"
      end
    end

    run_test({ file: file, class_name: class_name, test_case: test_case }) do |results|
      results = results[class_name]
      assert_equal 1, results[:tests], "expected only one test"
      assert_equal 1, results[:errors], "expected only one error"
      assert_equal 0, results[:assertions], "expected no assertions"
      assert_equal 0, results[:skipped], "expected no skips"
      assert results[:test_results].one?, "expected test results"
      test_result = results[:test_results].first

      assert test_result.error?, "epected an error"
      assert !test_result.passed?, "expected not to pass"
      assert !test_result.failure?, "expected not to fail"
      assert !test_result.skipped?, "expected not to skip"

      assert test_result.errors.one?
      error_msg = test_result.errors.first[:message]
      assert error_msg.include?("undefined method"), error_msg
    end
  end

  def test_io_error_with_retry_fails
    class_name = "IntegrationTestsTwo"
    test_case = "foo"
    file = new_test_file(class_name) do
      new_test_case(test_case) do
        "$stdout.fake('something')"
      end
    end

    run_test({ file: file, class_name: class_name, test_case: test_case, retries: 1 }) do |results|
      results = results[class_name]
      assert_equal 1, results[:tests], "expected only one test"
      assert_equal 1, results[:errors], "expected only one error"
      assert_equal 0, results[:assertions], "expected no assertions"
      assert_equal 0, results[:skipped], "expected no skips"
      assert results[:test_results].one?, "expected test results"
      test_result = results[:test_results].first

      assert !test_result.passed?, "expected to pass"
      assert test_result.error?, "epected an error"
      assert !test_result.failure?, "expected not to fail"
      assert !test_result.skipped?, "expected not to skip"

      assert test_result.errors.one?
      error_msg = test_result.errors.first[:message]
      assert error_msg.include?("undefined method"), error_msg
    end
  end

  def test_io_error_with_retry_succeeds
    class_name = "IntegrationTestsThree"
    test_case = "foo"
    bad_logic = "$stdout.fake('something')"
    file = new_test_file(class_name) do
      new_test_case(test_case) do
        bad_logic
      end
    end

    original_method = Minitest::Dispatch::Manager.instance_method(:process_object)
    Minitest::Dispatch::Manager.define_method(:original_process_object, original_method)
    Minitest::Dispatch::Manager.any_instance.stubs(:process_object).with do |object|
      if object[:action] == :test_result
        text = file.open.read
        puts = text.gsub(bad_logic, "puts 'hello'")
        file.close
        File.open(file.path, "w") { |file| file << puts }

        Minitest::Dispatch::Manager.unstub(:process_object)
      end
      @manager.original_process_object(object)
    end

    run_test({ file: file, class_name: class_name, test_case: test_case, retries: 1 }) do |results|
      results = results[class_name]
      assert_equal 1, results[:tests], "expected only one test"
      assert_equal 0, results[:errors], "expected only one error"
      assert_equal 0, results[:assertions], "expected no assertions"
      assert_equal 0, results[:skipped], "expected no skips"
      assert results[:test_results].one?, "expected test results"
      test_result = results[:test_results].first

      assert test_result.passed?, "expected to pass"
      assert !test_result.error?, "epected an error"
      assert !test_result.failure?, "expected not to fail"
      assert !test_result.skipped?, "expected not to skip"

      assert test_result.errors.none?
    end
  end

  def test_max_total_retries_fails
    class_name = "IntegrationTestsFour"
    test_case = "foo"
    file = new_test_file(class_name) do
      new_test_case(test_case) do
        "$stdout.fake('something')"
      end
    end
    options = {
      file: file,
      class_name: class_name,
      test_case: test_case,
      retries: 3,
      max_retries: 2
    }
    run_test(options) do |results|
      results = results[class_name]
      assert_equal 1, results[:tests], "expected only one test"
      assert_equal 1, results[:errors], "expected only one error"
      assert_equal 0, results[:assertions], "expected no assertions"
      assert_equal 0, results[:skipped], "expected no skips"
      assert results[:test_results].one?, "expected test results"
      test_result = results[:test_results].first

      assert !test_result.passed?, "expected to pass"
      assert test_result.error?, "epected an error"
      assert !test_result.failure?, "expected not to fail"
      assert !test_result.skipped?, "expected not to skip"

      assert test_result.errors.one?
      error_msg = test_result.errors.first[:message]
      assert error_msg.include?("undefined method"), error_msg
    end
  end
end
