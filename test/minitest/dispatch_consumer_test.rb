require "test_helper"

class DispatchConsumerTest < Minitest::Test
  def test_be_happy
    sleep 5
    puts "foo"
  end

  def test_fails
    sleep 5
    assert false, "This failed"
  end

  def test_exception
    sleep 5
    raise "not so good"
  end

  def test_skipped
    sleep 5
    skip
  end
end
