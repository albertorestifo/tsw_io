defmodule TswIo.Serial.Connection.StateTest do
  use ExUnit.Case, async: true

  alias TswIo.Serial.Connection.State
  alias TswIo.SerialTestHelpers

  describe "new state" do
    test "initializes with empty ports map" do
      # Arrange & Act
      state = %State{}

      # Assert
      assert state.ports == %{}
    end
  end

  describe "get/2" do
    test "returns connection when port exists" do
      # Arrange
      port = "/dev/tty.test1"
      conn = SerialTestHelpers.build_connected_connection(port: port)
      state = SerialTestHelpers.build_state([{port, conn}])

      # Act
      result = State.get(state, port)

      # Assert
      assert result == conn
    end

    test "returns nil when port does not exist" do
      # Arrange
      state = %State{}

      # Act
      result = State.get(state, "/dev/tty.nonexistent")

      # Assert
      assert result == nil
    end

    test "returns nil when state has other ports but not the requested one" do
      # Arrange
      port1 = "/dev/tty.test1"
      conn1 = SerialTestHelpers.build_connected_connection(port: port1)
      state = SerialTestHelpers.build_state([{port1, conn1}])

      # Act
      result = State.get(state, "/dev/tty.test2")

      # Assert
      assert result == nil
    end
  end

  describe "put/2" do
    test "adds a new connection to empty state" do
      # Arrange
      state = %State{}
      conn = SerialTestHelpers.build_connecting_connection(port: "/dev/tty.test")

      # Act
      updated_state = State.put(state, conn)

      # Assert
      assert map_size(updated_state.ports) == 1
      assert State.get(updated_state, "/dev/tty.test") == conn
    end

    test "adds a new connection to state with existing connections" do
      # Arrange
      port1 = "/dev/tty.test1"
      conn1 = SerialTestHelpers.build_connected_connection(port: port1)
      state = SerialTestHelpers.build_state([{port1, conn1}])

      port2 = "/dev/tty.test2"
      conn2 = SerialTestHelpers.build_connecting_connection(port: port2)

      # Act
      updated_state = State.put(state, conn2)

      # Assert
      assert map_size(updated_state.ports) == 2
      assert State.get(updated_state, port1) == conn1
      assert State.get(updated_state, port2) == conn2
    end

    test "replaces existing connection for same port" do
      # Arrange
      port = "/dev/tty.test"
      conn1 = SerialTestHelpers.build_connecting_connection(port: port)
      state = SerialTestHelpers.build_state([{port, conn1}])

      conn2 = SerialTestHelpers.build_connected_connection(port: port)

      # Act
      updated_state = State.put(state, conn2)

      # Assert
      assert map_size(updated_state.ports) == 1
      assert State.get(updated_state, port) == conn2
      assert State.get(updated_state, port).status == :connected
    end
  end

  describe "update/3" do
    test "updates existing connection using update function" do
      # Arrange
      port = "/dev/tty.test"
      conn = SerialTestHelpers.build_connecting_connection(port: port)
      state = SerialTestHelpers.build_state([{port, conn}])

      # Act
      updated_state =
        State.update(state, port, fn c ->
          %{c | status: :discovering}
        end)

      # Assert
      updated_conn = State.get(updated_state, port)
      assert updated_conn.status == :discovering
      assert updated_conn.port == port
    end

    test "does not modify state when port does not exist" do
      # Arrange
      state = %State{}

      # Act
      updated_state =
        State.update(state, "/dev/tty.nonexistent", fn c ->
          %{c | status: :failed}
        end)

      # Assert
      assert updated_state == state
      assert updated_state.ports == %{}
    end

    test "updates only the specified port when multiple ports exist" do
      # Arrange
      port1 = "/dev/tty.test1"
      port2 = "/dev/tty.test2"
      conn1 = SerialTestHelpers.build_connecting_connection(port: port1)
      conn2 = SerialTestHelpers.build_connected_connection(port: port2)
      state = SerialTestHelpers.build_state([{port1, conn1}, {port2, conn2}])

      # Act
      updated_state =
        State.update(state, port1, fn c ->
          %{c | status: :discovering}
        end)

      # Assert
      assert State.get(updated_state, port1).status == :discovering
      assert State.get(updated_state, port2).status == :connected
    end

    test "can be chained to update connection through state transitions" do
      # Arrange
      port = "/dev/tty.test"
      conn = SerialTestHelpers.build_connecting_connection(port: port)
      state = SerialTestHelpers.build_state([{port, conn}])

      # Act - simulate state machine progression
      updated_state =
        state
        |> State.update(port, fn c -> %{c | status: :discovering} end)
        |> State.update(port, fn c -> %{c | status: :connected} end)

      # Assert
      assert State.get(updated_state, port).status == :connected
    end
  end

  describe "delete/2" do
    test "removes connection from state" do
      # Arrange
      port = "/dev/tty.test"
      conn = SerialTestHelpers.build_connected_connection(port: port)
      state = SerialTestHelpers.build_state([{port, conn}])

      # Act
      updated_state = State.delete(state, port)

      # Assert
      assert State.get(updated_state, port) == nil
      assert map_size(updated_state.ports) == 0
    end

    test "does not modify state when port does not exist" do
      # Arrange
      state = %State{}

      # Act
      updated_state = State.delete(state, "/dev/tty.nonexistent")

      # Assert
      assert updated_state == state
    end

    test "removes only the specified port when multiple ports exist" do
      # Arrange
      port1 = "/dev/tty.test1"
      port2 = "/dev/tty.test2"
      conn1 = SerialTestHelpers.build_connected_connection(port: port1)
      conn2 = SerialTestHelpers.build_connected_connection(port: port2)
      state = SerialTestHelpers.build_state([{port1, conn1}, {port2, conn2}])

      # Act
      updated_state = State.delete(state, port1)

      # Assert
      assert State.get(updated_state, port1) == nil
      assert State.get(updated_state, port2) == conn2
      assert map_size(updated_state.ports) == 1
    end
  end

  describe "tracked?/2" do
    test "returns true when port exists in state" do
      # Arrange
      port = "/dev/tty.test"
      conn = SerialTestHelpers.build_connected_connection(port: port)
      state = SerialTestHelpers.build_state([{port, conn}])

      # Act
      result = State.tracked?(state, port)

      # Assert
      assert result == true
    end

    test "returns false when port does not exist in state" do
      # Arrange
      state = %State{}

      # Act
      result = State.tracked?(state, "/dev/tty.nonexistent")

      # Assert
      assert result == false
    end

    test "returns true for ports in any status" do
      # Arrange
      ports_by_status = [
        {"/dev/tty.connecting", SerialTestHelpers.build_connecting_connection(port: "/dev/tty.connecting")},
        {"/dev/tty.discovering", SerialTestHelpers.build_discovering_connection(port: "/dev/tty.discovering")},
        {"/dev/tty.connected", SerialTestHelpers.build_connected_connection(port: "/dev/tty.connected")},
        {"/dev/tty.disconnecting", SerialTestHelpers.build_disconnecting_connection(port: "/dev/tty.disconnecting")},
        {"/dev/tty.failed", SerialTestHelpers.build_failed_connection(port: "/dev/tty.failed")}
      ]

      state = SerialTestHelpers.build_state(ports_by_status)

      # Act & Assert
      for {port, _conn} <- ports_by_status do
        assert State.tracked?(state, port) == true
      end
    end
  end

  describe "connected_devices/1" do
    test "returns empty list when no connections exist" do
      # Arrange
      state = %State{}

      # Act
      result = State.connected_devices(state)

      # Assert
      assert result == []
    end

    test "returns only connections with :connected status" do
      # Arrange
      port_connected = "/dev/tty.connected"
      conn_connected = SerialTestHelpers.build_connected_connection(port: port_connected)

      port_connecting = "/dev/tty.connecting"
      conn_connecting = SerialTestHelpers.build_connecting_connection(port: port_connecting)

      port_discovering = "/dev/tty.discovering"
      conn_discovering = SerialTestHelpers.build_discovering_connection(port: port_discovering)

      state =
        SerialTestHelpers.build_state([
          {port_connected, conn_connected},
          {port_connecting, conn_connecting},
          {port_discovering, conn_discovering}
        ])

      # Act
      result = State.connected_devices(state)

      # Assert
      assert length(result) == 1
      assert hd(result) == conn_connected
      assert hd(result).status == :connected
    end

    test "returns multiple connected devices" do
      # Arrange
      device1 = SerialTestHelpers.build_device(id: 1)
      device2 = SerialTestHelpers.build_device(id: 2)

      port1 = "/dev/tty.test1"
      conn1 = SerialTestHelpers.build_connected_connection(port: port1, device: device1)

      port2 = "/dev/tty.test2"
      conn2 = SerialTestHelpers.build_connected_connection(port: port2, device: device2)

      state = SerialTestHelpers.build_state([{port1, conn1}, {port2, conn2}])

      # Act
      result = State.connected_devices(state)

      # Assert
      assert length(result) == 2
      assert conn1 in result
      assert conn2 in result
    end

    test "excludes :disconnecting and :failed connections" do
      # Arrange
      port_connected = "/dev/tty.connected"
      conn_connected = SerialTestHelpers.build_connected_connection(port: port_connected)

      port_disconnecting = "/dev/tty.disconnecting"
      conn_disconnecting = SerialTestHelpers.build_disconnecting_connection(port: port_disconnecting)

      port_failed = "/dev/tty.failed"
      conn_failed = SerialTestHelpers.build_failed_connection(port: port_failed)

      state =
        SerialTestHelpers.build_state([
          {port_connected, conn_connected},
          {port_disconnecting, conn_disconnecting},
          {port_failed, conn_failed}
        ])

      # Act
      result = State.connected_devices(state)

      # Assert
      assert length(result) == 1
      assert hd(result) == conn_connected
    end
  end
end
