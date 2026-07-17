require "test_helper"

class ChannelTest < Minitest::Test
  def setup
    # Stub EventMachine.attach so tests don't require a running event loop.
    # Tests focus purely on framing logic in receive_marshaled_data and process_read_buffer.
    @fake_connection = Object.new
    EventMachine.stubs(:attach).returns(@fake_connection)
  end

  def teardown
    EventMachine.unstub(:attach)
  end

  # Tests that a single marshal frame split across multiple receive_data callbacks
  # is correctly buffered and unmarshalled once complete.
  #
  # Simulates network fragmentation: a 25-byte payload might arrive as:
  #   - receive_data(3 bytes)   -- not enough for header, buffer it
  #   - receive_data(rest)      -- now complete frame, process and unmarshal
  def test_receive_object_handles_chunked_marshaled_payload
    channel = Minitest::Dispatch::Connection::Channel.new
    received = []

    channel.receive_object do |object|
      received << object
    end

    payload = Marshal.dump({ hello: "world", n: 1 })
    framed = [payload.bytesize].pack("N") + payload

    # Send 3 bytes (partial header), should not trigger receive_object callback
    first_chunk_size = 3
    channel.send(:receive_marshaled_data, framed.byteslice(0, first_chunk_size))
    assert_equal [], received

    # Send rest of frame, should unmarshal and trigger callback
    channel.send(:receive_marshaled_data, framed.byteslice(first_chunk_size..-1))
    assert_equal [{ hello: "world", n: 1 }], received
  end

  # Tests that multiple complete frames delivered in a single TCP packet
  # are all processed and unmarshalled.
  #
  # Simulates TCP coalescing: two separate send_object calls might arrive as:
  #   - receive_data( frame1 + frame2 )  -- process_read_buffer loops until no complete frames remain
  def test_receive_object_handles_multiple_framed_objects_in_one_chunk
    channel = Minitest::Dispatch::Connection::Channel.new
    received = []

    channel.receive_object do |object|
      received << object
    end

    one = Marshal.dump({ id: 1 })
    two = Marshal.dump({ id: 2 })
    # Concatenate two framed payloads
    framed = [one.bytesize].pack("N") + one + [two.bytesize].pack("N") + two

    # Single receive_data callback with both frames
    channel.send(:receive_marshaled_data, framed)

    # Both objects should be unmarshalled
    assert_equal [{ id: 1 }, { id: 2 }], received
  end
end

