require "test_helper"

class ProcessManagerTest < Minitest::Test
  def test_manager
    EventMachine.run do
      manager = Minitest::Dispatch::Process::Manager.new(cores: 2)
      manager.start
      children = manager.instance_variable_get("@children")
      assert_equal 2, children.count
      assert_equal 0, children[0].environment
      assert_equal 1, children[1].environment
      manager.stop
      EventMachine.stop
    end
  end

  def test_manager_with_offset
    EventMachine.run do
      manager = Minitest::Dispatch::Process::Manager.new(cores: 2, core_offset: 2)
      manager.start
      children = manager.instance_variable_get("@children")
      assert_equal 2, children.count
      assert_equal 2, children[0].environment
      assert_equal 3, children[1].environment
      manager.stop
      EventMachine.stop
    end
  end

  def test_killed_child_process
    EventMachine.run do
      manager = Minitest::Dispatch::Process::Manager.new(cores: 2, core_offset: 2)
      manager.start
      children = manager.instance_variable_get("@children")

      children.first.instance_variable_set("@status", :busy)
      assert_equal children.first.status, :busy

      pid = children.first.pid
      ::Process.kill("USR1", pid)

      EventMachine::Timer.new(1) do
        assert pid != children.first.pid, "Process should have restarted wth a different pid"
        assert_equal children.first.status, :ready

        manager.stop
        EventMachine.stop
      end
    end
  end
end
