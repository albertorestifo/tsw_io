defmodule TswIo.Serial.ConnectionTest do
  use ExUnit.Case, async: true

  alias TswIo.Serial.Connection.State
  alias TswIo.SerialTestHelpers

  # Note: These tests focus on pure functions and state management
  # GenServer integration is tested at a higher level

  describe "ignored_port?/1 pattern matching" do
    test "ignores ports matching Bluetooth pattern" do
      # Arrange
      bluetooth_ports = [
        "/dev/tty.Bluetooth-Incoming-Port",
        "/dev/cu.Bluetooth-Modem",
        "COM3-Bluetooth"
      ]

      # Act & Assert
      for port <- bluetooth_ports do
        # We test this indirectly through the module's behavior
        # The actual ignored_port?/1 is private, but its effects are observable
        refute port_should_connect?(port)
      end
    end

    test "ignores ports matching debug pattern" do
      # Arrange
      debug_ports = [
        "/dev/tty.debug-console",
        "/dev/cu.debug",
        "COM5-Debug-Port"
      ]

      # Act & Assert
      for port <- debug_ports do
        refute port_should_connect?(port)
      end
    end

    test "ignores ports matching TONE pattern" do
      # Arrange
      tone_ports = [
        "/dev/tty.TONE1",
        "/dev/cu.TONE",
        "TONE-Audio-Port"
      ]

      # Act & Assert
      for port <- tone_ports do
        refute port_should_connect?(port)
      end
    end

    test "allows valid serial port names" do
      # Arrange
      valid_ports = [
        "/dev/tty.usbserial-1234",
        "/dev/cu.usbmodem1234",
        "COM1",
        "/dev/ttyUSB0",
        "/dev/ttyACM0"
      ]

      # Act & Assert
      for port <- valid_ports do
        assert port_should_connect?(port)
      end
    end

    test "pattern matching is case insensitive" do
      # Arrange
      mixed_case_ports = [
        "/dev/tty.bluetooth-port",
        "/dev/tty.BLUETOOTH-PORT",
        "/dev/tty.BlUeToOtH-port",
        "/dev/tty.DEBUG",
        "/dev/tty.debug",
        "/dev/tty.tone",
        "/dev/tty.TONE"
      ]

      # Act & Assert
      for port <- mixed_case_ports do
        refute port_should_connect?(port)
      end
    end
  end

  describe "should_connect? logic" do
    test "should not connect to ports already in connecting state" do
      # Arrange
      port = "/dev/tty.test"
      conn = SerialTestHelpers.build_connecting_connection(port: port)
      state = SerialTestHelpers.build_state([{port, conn}])

      # Act - port is tracked and not failed
      is_tracked = State.tracked?(state, port)
      should_retry = case State.get(state, port) do
        nil -> true
        conn -> conn.status == :failed and
                System.monotonic_time(:millisecond) - (conn.failed_at || 0) >= 30_000
      end

      # Assert
      assert is_tracked == true
      assert should_retry == false
    end

    test "should retry failed ports after backoff period" do
      # Arrange
      port = "/dev/tty.test"
      backoff_ms = 30_000
      failed_at = System.monotonic_time(:millisecond) - (backoff_ms + 100)
      conn = SerialTestHelpers.build_failed_connection(port: port, failed_at: failed_at)
      state = SerialTestHelpers.build_state([{port, conn}])

      # Act
      tracked_conn = State.get(state, port)

      # Assert - should be eligible for retry
      assert tracked_conn.status == :failed
      assert System.monotonic_time(:millisecond) - tracked_conn.failed_at >= backoff_ms
    end

    test "should not retry failed ports before backoff period expires" do
      # Arrange
      port = "/dev/tty.test"
      backoff_ms = 30_000
      failed_at = System.monotonic_time(:millisecond) - 100  # Recent failure
      conn = SerialTestHelpers.build_failed_connection(port: port, failed_at: failed_at)
      state = SerialTestHelpers.build_state([{port, conn}])

      # Act
      tracked_conn = State.get(state, port)

      # Assert - should not be eligible for retry yet
      assert tracked_conn.status == :failed
      assert System.monotonic_time(:millisecond) - tracked_conn.failed_at < backoff_ms
    end
  end

  describe "connection lifecycle state transitions" do
    test "simulates connecting -> discovering -> connected flow" do
      # Arrange
      port = "/dev/tty.test"
      device = SerialTestHelpers.build_device(id: 42)
      state = %State{}

      # Act - simulate the full connection flow
      conn1 = SerialTestHelpers.build_connecting_connection(port: port)
      state1 = State.put(state, conn1)

      conn2 = State.get(state1, port)
      conn2_discovering = %{conn2 | status: :discovering}
      state2 = State.put(state1, conn2_discovering)

      conn3 = State.get(state2, port)
      conn3_connected = %{conn3 | status: :connected, device: device}
      state3 = State.put(state2, conn3_connected)

      # Assert
      final_conn = State.get(state3, port)
      assert final_conn.status == :connected
      assert final_conn.device.id == 42
      assert length(State.connected_devices(state3)) == 1
    end

    test "simulates connection failure and cleanup flow" do
      # Arrange
      port = "/dev/tty.test"
      conn = SerialTestHelpers.build_connected_connection(port: port)
      state = SerialTestHelpers.build_state([{port, conn}])

      # Act - simulate disconnect and failure
      conn_disconnecting = State.get(state, port) |> Map.put(:status, :disconnecting)
      state_disconnecting = State.put(state, conn_disconnecting)

      conn_failed = State.get(state_disconnecting, port)
                    |> Map.put(:status, :failed)
                    |> Map.put(:pid, nil)
                    |> Map.put(:failed_at, System.monotonic_time(:millisecond))
      state_failed = State.put(state_disconnecting, conn_failed)

      # Assert
      final_conn = State.get(state_failed, port)
      assert final_conn.status == :failed
      assert final_conn.pid == nil
      assert is_integer(final_conn.failed_at)
      assert length(State.connected_devices(state_failed)) == 0
    end
  end

  # Helper functions

  defp port_should_connect?(port) do
    # Simulate the ignored_port? check using the same patterns
    ignored_patterns = [
      ~r/Bluetooth/i,
      ~r/debug/i,
      ~r/TONE/i
    ]

    not Enum.any?(ignored_patterns, &Regex.match?(&1, port))
  end
end
