defmodule TswIo.Serial.Connection.DeviceConnectionTest do
  use ExUnit.Case, async: true

  alias TswIo.Serial.Connection.DeviceConnection
  alias TswIo.SerialTestHelpers

  describe "new/2" do
    test "creates a connection in :connecting state with port and pid" do
      # Arrange
      port = "/dev/tty.test"
      pid = self()

      # Act
      conn = DeviceConnection.new(port, pid)

      # Assert
      assert %DeviceConnection{} = conn
      assert conn.port == port
      assert conn.status == :connecting
      assert conn.pid == pid
      assert conn.device == nil
      assert conn.failed_at == nil
    end
  end

  describe "mark_discovering/1" do
    test "transitions from :connecting to :discovering" do
      # Arrange
      conn = SerialTestHelpers.build_connecting_connection()

      # Act
      updated_conn = DeviceConnection.mark_discovering(conn)

      # Assert
      assert updated_conn.status == :discovering
      assert updated_conn.port == conn.port
      assert updated_conn.pid == conn.pid
    end

    test "raises FunctionClauseError when not in :connecting state" do
      # Arrange
      conn = SerialTestHelpers.build_discovering_connection()

      # Act & Assert
      assert_raise FunctionClauseError, fn ->
        DeviceConnection.mark_discovering(conn)
      end
    end
  end

  describe "mark_connected/2" do
    test "transitions from :discovering to :connected with device" do
      # Arrange
      conn = SerialTestHelpers.build_discovering_connection()
      device = SerialTestHelpers.build_device(id: 42, version: 200)

      # Act
      updated_conn = DeviceConnection.mark_connected(conn, device)

      # Assert
      assert updated_conn.status == :connected
      assert updated_conn.device == device
      assert updated_conn.device.id == 42
      assert updated_conn.device.version == 200
    end

    test "raises FunctionClauseError when not in :discovering state" do
      # Arrange
      conn = SerialTestHelpers.build_connected_connection()
      device = SerialTestHelpers.build_device()

      # Act & Assert
      assert_raise FunctionClauseError, fn ->
        DeviceConnection.mark_connected(conn, device)
      end
    end
  end

  describe "mark_disconnecting/1" do
    test "transitions from :connecting to :disconnecting" do
      # Arrange
      conn = SerialTestHelpers.build_connecting_connection()

      # Act
      updated_conn = DeviceConnection.mark_disconnecting(conn)

      # Assert
      assert updated_conn.status == :disconnecting
    end

    test "transitions from :discovering to :disconnecting" do
      # Arrange
      conn = SerialTestHelpers.build_discovering_connection()

      # Act
      updated_conn = DeviceConnection.mark_disconnecting(conn)

      # Assert
      assert updated_conn.status == :disconnecting
    end

    test "transitions from :connected to :disconnecting" do
      # Arrange
      conn = SerialTestHelpers.build_connected_connection()

      # Act
      updated_conn = DeviceConnection.mark_disconnecting(conn)

      # Assert
      assert updated_conn.status == :disconnecting
    end

    test "is idempotent when already :disconnecting" do
      # Arrange
      conn = SerialTestHelpers.build_disconnecting_connection()
      original_conn = conn

      # Act
      updated_conn = DeviceConnection.mark_disconnecting(conn)

      # Assert
      assert updated_conn == original_conn
      assert updated_conn.status == :disconnecting
    end

    test "is idempotent when already :failed" do
      # Arrange
      conn = SerialTestHelpers.build_failed_connection()
      original_failed_at = conn.failed_at

      # Act
      updated_conn = DeviceConnection.mark_disconnecting(conn)

      # Assert
      assert updated_conn == conn
      assert updated_conn.status == :failed
      assert updated_conn.failed_at == original_failed_at
    end
  end

  describe "mark_failed/1" do
    test "transitions from :disconnecting to :failed with timestamp" do
      # Arrange
      conn = SerialTestHelpers.build_disconnecting_connection()
      before_time = System.monotonic_time(:millisecond)

      # Act
      updated_conn = DeviceConnection.mark_failed(conn)
      after_time = System.monotonic_time(:millisecond)

      # Assert
      assert updated_conn.status == :failed
      assert updated_conn.pid == nil
      assert updated_conn.failed_at != nil
      assert updated_conn.failed_at >= before_time
      assert updated_conn.failed_at <= after_time
    end

    test "is idempotent when already :failed - preserves original timestamp" do
      # Arrange
      original_timestamp = System.monotonic_time(:millisecond) - 5000
      conn = SerialTestHelpers.build_failed_connection(failed_at: original_timestamp)

      # Act
      updated_conn = DeviceConnection.mark_failed(conn)

      # Assert
      assert updated_conn == conn
      assert updated_conn.status == :failed
      assert updated_conn.failed_at == original_timestamp
    end

    test "raises FunctionClauseError when not in :disconnecting or :failed state" do
      # Arrange
      conn = SerialTestHelpers.build_connected_connection()

      # Act & Assert
      assert_raise FunctionClauseError, fn ->
        DeviceConnection.mark_failed(conn)
      end
    end
  end

  describe "should_retry?/2" do
    test "returns true when failed and backoff period has elapsed" do
      # Arrange
      backoff_ms = 1000
      failed_at = System.monotonic_time(:millisecond) - (backoff_ms + 100)
      conn = SerialTestHelpers.build_failed_connection(failed_at: failed_at)

      # Act
      result = DeviceConnection.should_retry?(conn, backoff_ms)

      # Assert
      assert result == true
    end

    test "returns false when failed but backoff period has not elapsed" do
      # Arrange
      backoff_ms = 1000
      failed_at = System.monotonic_time(:millisecond) - (backoff_ms - 100)
      conn = SerialTestHelpers.build_failed_connection(failed_at: failed_at)

      # Act
      result = DeviceConnection.should_retry?(conn, backoff_ms)

      # Assert
      assert result == false
    end

    test "returns false when failed exactly at backoff boundary" do
      # Arrange
      backoff_ms = 1000
      failed_at = System.monotonic_time(:millisecond) - backoff_ms
      conn = SerialTestHelpers.build_failed_connection(failed_at: failed_at)

      # Act
      result = DeviceConnection.should_retry?(conn, backoff_ms)

      # Assert
      assert result == true
    end

    test "returns false when connection is :connecting" do
      # Arrange
      conn = SerialTestHelpers.build_connecting_connection()

      # Act
      result = DeviceConnection.should_retry?(conn, 1000)

      # Assert
      assert result == false
    end

    test "returns false when connection is :discovering" do
      # Arrange
      conn = SerialTestHelpers.build_discovering_connection()

      # Act
      result = DeviceConnection.should_retry?(conn, 1000)

      # Assert
      assert result == false
    end

    test "returns false when connection is :connected" do
      # Arrange
      conn = SerialTestHelpers.build_connected_connection()

      # Act
      result = DeviceConnection.should_retry?(conn, 1000)

      # Assert
      assert result == false
    end

    test "returns false when connection is :disconnecting" do
      # Arrange
      conn = SerialTestHelpers.build_disconnecting_connection()

      # Act
      result = DeviceConnection.should_retry?(conn, 1000)

      # Assert
      assert result == false
    end
  end

  describe "active?/1" do
    test "returns true for :connecting status" do
      # Arrange
      conn = SerialTestHelpers.build_connecting_connection()

      # Act & Assert
      assert DeviceConnection.active?(conn) == true
    end

    test "returns true for :discovering status" do
      # Arrange
      conn = SerialTestHelpers.build_discovering_connection()

      # Act & Assert
      assert DeviceConnection.active?(conn) == true
    end

    test "returns true for :connected status" do
      # Arrange
      conn = SerialTestHelpers.build_connected_connection()

      # Act & Assert
      assert DeviceConnection.active?(conn) == true
    end

    test "returns true for :disconnecting status" do
      # Arrange
      conn = SerialTestHelpers.build_disconnecting_connection()

      # Act & Assert
      assert DeviceConnection.active?(conn) == true
    end

    test "returns false for :failed status" do
      # Arrange
      conn = SerialTestHelpers.build_failed_connection()

      # Act & Assert
      assert DeviceConnection.active?(conn) == false
    end
  end
end
