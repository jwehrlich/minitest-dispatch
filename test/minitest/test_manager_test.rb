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
end
