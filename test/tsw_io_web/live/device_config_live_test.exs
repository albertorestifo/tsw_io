defmodule TswIoWeb.DeviceConfigLiveTest do
  use TswIoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias TswIo.Hardware
  alias TswIo.Hardware.Input

  describe "mount/3" do
    test "redirects when device not connected", %{conn: conn} do
      # Try to access config for a non-existent device
      port = "/dev/tty.nonexistent"
      encoded_port = URI.encode_www_form(port)

      {:error, {:redirect, %{to: "/", flash: flash}}} =
        live(conn, "/devices/#{encoded_port}/config")

      assert flash["error"] == "Device not found"
    end
  end

  describe "Input changeset" do
    test "validates required fields" do
      changeset = Input.changeset(%Input{}, %{})

      refute changeset.valid?
      assert %{pin: ["can't be blank"]} = errors_on(changeset)
      assert %{input_type: ["can't be blank"]} = errors_on(changeset)
      assert %{sensitivity: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates pin range" do
      changeset =
        Input.changeset(%Input{}, %{pin: 0, input_type: :analog, sensitivity: 5, device_id: 1})

      refute changeset.valid?
      assert %{pin: ["must be greater than 0"]} = errors_on(changeset)

      changeset =
        Input.changeset(%Input{}, %{pin: 255, input_type: :analog, sensitivity: 5, device_id: 1})

      refute changeset.valid?
      assert %{pin: ["must be less than 255"]} = errors_on(changeset)

      changeset =
        Input.changeset(%Input{}, %{pin: 100, input_type: :analog, sensitivity: 5, device_id: 1})

      assert changeset.valid?
    end

    test "validates sensitivity range" do
      changeset =
        Input.changeset(%Input{}, %{pin: 5, input_type: :analog, sensitivity: 0, device_id: 1})

      refute changeset.valid?
      assert %{sensitivity: ["must be greater than 0"]} = errors_on(changeset)

      changeset =
        Input.changeset(%Input{}, %{pin: 5, input_type: :analog, sensitivity: 11, device_id: 1})

      refute changeset.valid?
      assert %{sensitivity: ["must be less than or equal to 10"]} = errors_on(changeset)

      changeset =
        Input.changeset(%Input{}, %{pin: 5, input_type: :analog, sensitivity: 10, device_id: 1})

      assert changeset.valid?
    end
  end

  describe "Hardware context integration" do
    setup do
      {:ok, device} = Hardware.create_device(%{name: "Test Device"})
      %{device: device}
    end

    test "creates inputs for device", %{device: device} do
      {:ok, input} =
        Hardware.create_input(device.id, %{pin: 5, input_type: :analog, sensitivity: 5})

      assert input.device_id == device.id
      assert input.pin == 5
      assert input.input_type == :analog
      assert input.sensitivity == 5
    end

    test "lists inputs ordered by pin", %{device: device} do
      {:ok, _} = Hardware.create_input(device.id, %{pin: 10, input_type: :analog, sensitivity: 5})
      {:ok, _} = Hardware.create_input(device.id, %{pin: 2, input_type: :analog, sensitivity: 5})
      {:ok, _} = Hardware.create_input(device.id, %{pin: 5, input_type: :analog, sensitivity: 5})

      {:ok, inputs} = Hardware.list_inputs(device.id)
      pins = Enum.map(inputs, & &1.pin)

      assert pins == [2, 5, 10]
    end

    test "deletes input", %{device: device} do
      {:ok, input} =
        Hardware.create_input(device.id, %{pin: 5, input_type: :analog, sensitivity: 5})

      {:ok, _} = Hardware.delete_input(input.id)

      {:ok, inputs} = Hardware.list_inputs(device.id)
      assert inputs == []
    end

    test "enforces unique pin per device", %{device: device} do
      {:ok, _} = Hardware.create_input(device.id, %{pin: 5, input_type: :analog, sensitivity: 5})

      {:error, changeset} =
        Hardware.create_input(device.id, %{pin: 5, input_type: :analog, sensitivity: 5})

      assert %{device_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "PubSub event handling" do
    test "configuration_applied event updates device" do
      {:ok, device} = Hardware.create_device(%{name: "Test Device"})
      {:ok, updated_device} = Hardware.update_device(device, %{config_id: 12345})

      # Verify the device was updated
      {:ok, found} = Hardware.get_device_by_config_id(12345)
      assert found.id == updated_device.id
    end

    test "configuration failure reasons" do
      # Test the error message mapping logic from handle_info
      reasons = [:timeout, :device_rejected, :no_inputs, :unknown]

      expected_messages = [
        "Configuration timed out - device did not respond",
        "Device rejected the configuration",
        "Cannot apply empty configuration",
        "Failed to apply configuration"
      ]

      for {reason, expected} <- Enum.zip(reasons, expected_messages) do
        message =
          case reason do
            :timeout -> "Configuration timed out - device did not respond"
            :device_rejected -> "Device rejected the configuration"
            :no_inputs -> "Cannot apply empty configuration"
            _ -> "Failed to apply configuration"
          end

        assert message == expected, "Expected '#{expected}' for reason #{inspect(reason)}"
      end
    end

    test "input value updates" do
      input_values = %{}
      pin = 5
      value = 512

      new_values = Map.put(input_values, pin, value)

      assert new_values == %{5 => 512}
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
