require "test_helper"

class ChildTest < Minitest::Test
  class FakeChannel
    attr_reader :receive_object_block

    def receive_object(&block)
      @receive_object_block = block
    end

    def trigger_receive_object(object)
      @receive_object_block.call(object)
    end

    def close_connections; end

    def send_object(_object); end
  end

  def test_scheduled_test_case_marks_child_busy_and_sends_to_child_channel
    child = build_child(status: :ready)
    test_case = Object.new
    channel_to_child = mock("channel_to_child")

    channel_to_child.expects(:send_object).with(test_case)
    child.instance_variable_set("@channel_to_child", channel_to_child)

    child.scheduled_test_case(test_case)

    assert_equal :busy, child.status
    assert_equal test_case, child.current_test_case
  end

  def test_scheduled_test_case_while_busy_triggers_failed_to_process
    child = build_child(status: :busy)
    test_case = Object.new
    captured = nil

    # Keep current behavior stable while this branch still calls Log(...).
    child.stubs(:Log)
    child.add_callback(:failed_to_process) { |object| captured = object }

    child.scheduled_test_case(test_case)

    assert_equal({ test_case: test_case }, captured)
  end

  def test_close_connections_clears_callbacks_and_closes_channels
    child = build_child(status: :ready)
    channel_to_child = mock("channel_to_child")
    channel_to_parent = mock("channel_to_parent")

    channel_to_child.expects(:close_connections)
    channel_to_parent.expects(:close_connections)

    child.instance_variable_set("@channel_to_child", channel_to_child)
    child.instance_variable_set("@channel_to_parent", channel_to_parent)
    child.add_callback(:test_finished, &proc {})

    child.close_connections

    assert_equal({}, child.instance_variable_get("@callbacks_collection"))
  end

  def test_kill_process_triggers_reschedule_for_running_test_and_clears_pid
    child = build_child(status: :ready, pid: 123)
    running_test = Object.new
    captured = nil

    child.instance_variable_set("@current_test_case", running_test)
    child.stubs(:log)
    child.add_callback(:failed_to_process) { |object| captured = object }
    stub_channels_for_close(child)

    ::Process.expects(:getpgid).with(123).returns(1)
    ::Process.expects(:kill).with("USR1", 123)

    child.kill_process

    assert_equal :busy, child.status
    assert_nil child.pid
    assert_equal running_test, captured[:test_case]
    assert_equal true, captured[:options][:bad_core]
  end

  def test_kill_process_ignores_missing_process
    child = build_child(status: :ready, pid: 321)

    child.stubs(:log)
    stub_channels_for_close(child)

    ::Process.expects(:getpgid).with(321).raises(Errno::ESRCH)
    ::Process.expects(:kill).never

    child.kill_process

    assert_nil child.pid
  end

  def test_run_test_case_sets_test_env_number_and_restores_it
    child = build_child(status: :ready, environment: 7)
    test_case = mock("test_case")
    channel_to_parent = mock("channel_to_parent")
    previous_env = ENV.fetch("TEST_ENV_NUMBER", nil)

    child.stubs(:log)
    child.instance_variable_set("@channel_to_parent", channel_to_parent)

    ENV["TEST_ENV_NUMBER"] = "orig"
    test_case.expects(:run).returns(:result)
    channel_to_parent.expects(:send_object).with(:result)

    child.send(:run_test_case, test_case)

    assert_equal "orig", ENV.fetch("TEST_ENV_NUMBER", nil)
  ensure
    ENV["TEST_ENV_NUMBER"] = previous_env
  end

  def test_run_test_case_restores_env_when_test_raises
    child = build_child(status: :ready, environment: 4)
    test_case = mock("test_case")
    channel_to_parent = mock("channel_to_parent")
    previous_env = ENV.fetch("TEST_ENV_NUMBER", nil)

    child.stubs(:log)
    child.instance_variable_set("@channel_to_parent", channel_to_parent)

    ENV["TEST_ENV_NUMBER"] = "orig"
    test_case.expects(:run).raises(RuntimeError.new("boom"))
    channel_to_parent.expects(:send_object).never

    assert_raises(RuntimeError) { child.send(:run_test_case, test_case) }
    assert_equal "orig", ENV.fetch("TEST_ENV_NUMBER", nil)
  ensure
    ENV["TEST_ENV_NUMBER"] = previous_env
  end

  def test_run_test_case_logs_running_message
    child = build_child(status: :ready, environment: 9, pid: 222)
    test_case = mock("test_case")
    channel_to_parent = mock("channel_to_parent")
    previous_env = ENV.fetch("TEST_ENV_NUMBER", nil)

    child.instance_variable_set("@channel_to_parent", channel_to_parent)
    child.stubs(:to_s).returns("#<Child pid: 222, parent_pid: 999, environment: 9>")

    ENV["TEST_ENV_NUMBER"] = "orig"
    test_case.expects(:run).returns(:ok)
    channel_to_parent.expects(:send_object).with(:ok)
    child.expects(:log).with do |msg|
      assert_includes msg, "Running test case:"
      assert_includes msg, test_case.to_s
      assert_includes msg, "on #<Child pid: 222, parent_pid: 999, environment: 9>"
      assert_includes msg, "TEST_ENV_NUMBER: 9"
      true
    end

    child.send(:run_test_case, test_case)
    assert_equal "orig", ENV.fetch("TEST_ENV_NUMBER", nil)
  ensure
    ENV["TEST_ENV_NUMBER"] = previous_env
  end

  def test_start_forked_process_wires_channel_callbacks
    child = build_child(status: :busy, environment: 2, pid: nil)
    channel_to_child = FakeChannel.new
    channel_to_parent = FakeChannel.new
    captured_result = nil

    child.stubs(:log)
    child.add_callback(:test_finished) { |result| captured_result = result }

    ::Minitest::Dispatch::Connection::Channel.stubs(:new).returns(channel_to_child, channel_to_parent)
    EventMachine.expects(:fork_reactor).yields.returns(777)
    ::Process.stubs(:pid).returns(555)
    ::Process.expects(:detach).with(777)
    child.expects(:run_test_case).with(:test_payload)

    child.send(:start_forked_process)

    child.instance_variable_set("@status", :busy)
    child.instance_variable_set("@current_test_case", :in_progress)

    channel_to_child.trigger_receive_object(:test_payload)
    channel_to_parent.trigger_receive_object(:done)

    assert_equal 777, child.pid
    assert_equal :ready, child.status
    assert_nil child.current_test_case
    assert_equal :done, captured_result
  end

  def test_log_includes_process_context
    child = build_child(status: :ready, environment: 3, pid: 456)

    ::Process.stubs(:pid).returns(1111)
    Minitest::Dispatch::Logger.expects(:debug).with do |message|
      assert_includes message, "[999.456.3]"
      assert_includes message, "[1111]"
      assert_includes message, "hello logger"
      true
    end

    child.send(:log, "hello logger", level: :debug)
  ensure
    ::Process.unstub(:pid)
  end

  private

  def build_child(status:, environment: 0, pid: 1)
    child = Minitest::Dispatch::Process::Child.allocate
    child.instance_variable_set("@semaphore", Thread::Mutex.new)
    child.instance_variable_set("@status", status)
    child.instance_variable_set("@environment", environment)
    child.instance_variable_set("@current_test_case", nil)
    child.instance_variable_set("@parent_pid", 999)
    child.instance_variable_set("@pid", pid)
    child
  end

  def stub_channels_for_close(child)
    channel_to_child = mock("channel_to_child")
    channel_to_parent = mock("channel_to_parent")

    channel_to_child.expects(:close_connections)
    channel_to_parent.expects(:close_connections)

    child.instance_variable_set("@channel_to_child", channel_to_child)
    child.instance_variable_set("@channel_to_parent", channel_to_parent)
  end
end
