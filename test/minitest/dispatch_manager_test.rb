require "test_helper"

class DispatchManagerTest < Minitest::Test
  def test_be_happy_one
    puts "**** HAPPY TEST ONE ENVIRONMENT: #{ENV.fetch("TEST_ENV_NUMBER")} ****"
  end

  def test_be_happy_two
    puts "**** HAPPY TEST TWO ENVIRONMENT: #{ENV.fetch("TEST_ENV_NUMBER")} ****"
  end
end
