require "eventmachine"

module Minitest
  module Dispatch
    module Connection
      # This creates a communication tunnel between forked processes and the parent task.
      class Channel
        include CallbacksMixin

        def initialize
          @io_read, @io_write = IO.pipe
        end

        def receive_data(&block)
          add_callback(:receive_data, &block)
        end

        def receive_object(&block)
          setup_read
          add_callback(:receive_object, &block)
        end

        def send_data(data)
          write.send_data(data)
        end

        def send_object(object)
          payload = Marshal.dump(object)
          # Prefix payload with a 4-byte big-endian length header so receiver can
          # reassemble complete frames before calling Marshal.load.
          send_data([payload.bytesize].pack("N") + payload)
        end

        def close_connections
          @read.close_connection_after_writing if defined? @read
          @write.close_connection_after_writing if defined? @write
        end

        private

        def setup_read
          @read ||= EventMachine.attach(@io_read, Unbound)
          @read_buffer ||= +""

          me = self
          @read.define_singleton_method :receive_data do |data|
            me.send(:receive_marshaled_data, data)
          end
        end

        # Receives raw data from EventMachine and buffers it for frame parsing.
        # EventMachine may deliver a single send_object call across multiple receive_data
        # callbacks due to TCP fragmentation. This method appends to the buffer and
        # delegates to process_read_buffer to unmarshal complete frames.
        #
        # @param data [String] raw bytes received from EventMachine
        def receive_marshaled_data(data)
          trigger_callback(:receive_data, data)
          @read_buffer << data
          process_read_buffer
        end

        # Processes the read buffer, unmarshalling complete length-prefixed frames.
        # Uses a simple framing protocol: [4-byte big-endian length] + [payload bytes]
        #
        # Loop behavior:
        #   - Breaks if fewer than 4 bytes available (need header)
        #   - Breaks if payload_length is nil/unparseable (corrupted header)
        #   - Breaks if fewer than (4 + payload_length) bytes available (incomplete frame)
        #   - Unmarshals and triggers :receive_object callback once frame is complete
        #   - Continues processing remaining buffered data (handles multiple frames in one chunk)
        #
        # Edge cases handled:
        #   - Partial headers (< 4 bytes): waits for more data
        #   - Payload split across chunks: buffers until complete
        #   - Multiple frames in one deliver: processes all available complete frames
        #   - Malformed length header: breaks gracefully, logs nothing (connection will timeout)
        #   - byteslice returning nil on out-of-bounds: explicit nil checks prevent unmarshal errors
        def process_read_buffer
          loop do
            break if @read_buffer.bytesize < 4

            payload_length = @read_buffer.byteslice(0, 4).unpack1("N")
            break if payload_length.nil?

            payload_length = Integer(payload_length)

            frame_length = 4 + payload_length
            break if @read_buffer.bytesize < frame_length

            payload = @read_buffer.byteslice(4, payload_length)
            break if payload.nil?

            @read_buffer = @read_buffer.byteslice(frame_length..-1) || +""
            trigger_callback(:receive_object, Marshal.load(payload))
          end
        end

        private :receive_marshaled_data, :process_read_buffer

        def write
          @write ||= EventMachine.attach(@io_write)
        end
      end
    end
  end
end
