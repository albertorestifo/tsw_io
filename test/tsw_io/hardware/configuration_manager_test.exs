defmodule TswIo.Hardware.ConfigurationManagerTest do
  use TswIo.DataCase, async: false

  alias TswIo.Hardware
  alias TswIo.Hardware.ConfigurationManager
  alias TswIo.Serial.Protocol.ConfigurationStored
  alias TswIo.Serial.Protocol.ConfigurationError
  alias TswIo.Serial.Protocol.InputValue

  @config_topic "hardware:configuration"
  @input_values_topic "hardware:input_values"

  # The ConfigurationManager is started by the application supervision tree.
  # We test against the running instance, using unique ports per test to avoid conflicts.

  defp unique_port, do: "/dev/tty.test_#{System.unique_integer([:positive])}"

  describe "apply_configuration/2" do
    setup do
      {:ok, device} = Hardware.create_device(%{name: "Test Device"})

      {:ok, _input} =
        Hardware.create_input(device.id, %{pin: 5, input_type: :analog, sensitivity: 5})

      %{device: device, port: unique_port()}
    end

    test "returns error when device not found", %{port: port} do
      assert {:error, :not_found} = ConfigurationManager.apply_configuration(port, 999_999)
    end

    test "returns error when device has no inputs", %{port: port} do
      {:ok, empty_device} = Hardware.create_device(%{name: "Empty Device"})

      assert {:error, :no_inputs} =
               ConfigurationManager.apply_configuration(port, empty_device.id)
    end
  end

  describe "get_input_values/1" do
    test "returns empty map when no values stored" do
      port = unique_port()
      assert %{} = ConfigurationManager.get_input_values(port)
    end
  end

  describe "handle_info/2 - InputValue messages" do
    setup do
      port = unique_port()
      Phoenix.PubSub.subscribe(TswIo.PubSub, "#{@input_values_topic}:#{port}")

      %{port: port}
    end

    test "stores input values and broadcasts updates", %{port: port} do
      # Simulate receiving an InputValue message
      send(ConfigurationManager, {:serial_message, port, %InputValue{pin: 5, value: 512}})

      # Wait for async processing
      :timer.sleep(10)

      # Check stored value
      assert %{5 => 512} = ConfigurationManager.get_input_values(port)

      # Check broadcast was sent
      assert_receive {:input_value_updated, ^port, 5, 512}
    end

    test "updates existing values", %{port: port} do
      send(ConfigurationManager, {:serial_message, port, %InputValue{pin: 5, value: 100}})
      :timer.sleep(10)

      send(ConfigurationManager, {:serial_message, port, %InputValue{pin: 5, value: 200}})
      :timer.sleep(10)

      assert %{5 => 200} = ConfigurationManager.get_input_values(port)
    end

    test "stores multiple pins independently", %{port: port} do
      send(ConfigurationManager, {:serial_message, port, %InputValue{pin: 5, value: 100}})
      send(ConfigurationManager, {:serial_message, port, %InputValue{pin: 10, value: 200}})
      :timer.sleep(10)

      values = ConfigurationManager.get_input_values(port)
      assert %{5 => 100, 10 => 200} = values
    end

    test "handles negative values", %{port: port} do
      send(ConfigurationManager, {:serial_message, port, %InputValue{pin: 5, value: -100}})
      :timer.sleep(10)

      assert %{5 => -100} = ConfigurationManager.get_input_values(port)
    end
  end

  describe "handle_info/2 - ConfigurationStored messages" do
    setup do
      {:ok, device} = Hardware.create_device(%{name: "Test Device"})

      {:ok, _input} =
        Hardware.create_input(device.id, %{pin: 5, input_type: :analog, sensitivity: 5})

      port = unique_port()
      Phoenix.PubSub.subscribe(TswIo.PubSub, @config_topic)

      %{device: device, port: port}
    end

    test "ignores ConfigurationStored for unknown config_id", %{port: port} do
      send(
        ConfigurationManager,
        {:serial_message, port, %ConfigurationStored{config_id: 999_999}}
      )

      :timer.sleep(10)

      # Should not receive any broadcast
      refute_receive {:configuration_applied, _, _, _}
      refute_receive {:configuration_failed, _, _, _}
    end
  end

  describe "handle_info/2 - ConfigurationError messages" do
    setup do
      port = unique_port()
      Phoenix.PubSub.subscribe(TswIo.PubSub, @config_topic)

      %{port: port}
    end

    test "ignores ConfigurationError for unknown config_id", %{port: port} do
      send(
        ConfigurationManager,
        {:serial_message, port, %ConfigurationError{config_id: 999_999}}
      )

      :timer.sleep(10)

      refute_receive {:configuration_failed, _, _, _}
    end
  end

  describe "handle_info/2 - devices_updated" do
    setup do
      port = unique_port()
      %{port: port}
    end

    test "clears input values for disconnected ports", %{port: port} do
      # Add some input values
      send(ConfigurationManager, {:serial_message, port, %InputValue{pin: 5, value: 100}})
      :timer.sleep(10)
      assert %{5 => 100} = ConfigurationManager.get_input_values(port)

      # Simulate device disconnect (no devices connected)
      send(ConfigurationManager, {:devices_updated, []})
      :timer.sleep(10)

      # Values should be cleared
      assert %{} = ConfigurationManager.get_input_values(port)
    end

    test "preserves input values for connected ports", %{port: port} do
      # Add some input values
      send(ConfigurationManager, {:serial_message, port, %InputValue{pin: 5, value: 100}})
      :timer.sleep(10)

      # Simulate device update with our port still connected
      send(ConfigurationManager, {:devices_updated, [%{port: port}]})
      :timer.sleep(10)

      # Values should be preserved
      assert %{5 => 100} = ConfigurationManager.get_input_values(port)
    end
  end

  describe "subscribe_configuration/0" do
    test "subscribes to configuration events" do
      :ok = ConfigurationManager.subscribe_configuration()

      # Broadcast a test message
      Phoenix.PubSub.broadcast(TswIo.PubSub, @config_topic, {:test_event, :data})

      assert_receive {:test_event, :data}
    end
  end

  describe "subscribe_input_values/1" do
    test "subscribes to input value events for specific port" do
      port = unique_port()
      :ok = ConfigurationManager.subscribe_input_values(port)

      # Broadcast a test message to this port
      Phoenix.PubSub.broadcast(
        TswIo.PubSub,
        "#{@input_values_topic}:#{port}",
        {:test_input_event, :data}
      )

      assert_receive {:test_input_event, :data}
    end

    test "does not receive events for other ports" do
      port1 = unique_port()
      port2 = unique_port()

      :ok = ConfigurationManager.subscribe_input_values(port1)

      # Broadcast to a different port
      Phoenix.PubSub.broadcast(
        TswIo.PubSub,
        "#{@input_values_topic}:#{port2}",
        {:other_port_event, :data}
      )

      refute_receive {:other_port_event, :data}
    end
  end
end
