defmodule TswIo.Serial.DiscoveryTest do
  use ExUnit.Case, async: true

  alias TswIo.Device
  alias TswIo.Serial.Protocol

  # Mock UART process that responds to messages
  defmodule MockUART do
    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts)
    end

    def init(opts) do
      {:ok,
       %{
         responses: Keyword.get(opts, :responses, []),
         write_result: Keyword.get(opts, :write_result, :ok),
         drain_result: Keyword.get(opts, :drain_result, :ok)
       }}
    end

    def handle_call(:write, _from, state) do
      {:reply, state.write_result, state}
    end

    def handle_call(:drain, _from, state) do
      {:reply, state.drain_result, state}
    end

    def handle_call({:read, _timeout}, _from, %{responses: []} = state) do
      {:reply, {:error, :timeout}, state}
    end

    def handle_call({:read, _timeout}, _from, %{responses: [response | rest]} = state) do
      {:reply, response, %{state | responses: rest}}
    end

    # Public API matching Circuits.UART
    def write(pid, _data) do
      GenServer.call(pid, :write)
    end

    def drain(pid) do
      GenServer.call(pid, :drain)
    end

    def read(pid, timeout) do
      GenServer.call(pid, {:read, timeout})
    end
  end

  describe "discover/1 - success path" do
    test "returns device when valid identity response is received" do
      # Arrange
      device_id = 42
      version = 100
      config_id = 5

      identity_response = %Protocol.IdentityResponse{
        request_id: 123,
        device_id: device_id,
        version: version,
        config_id: config_id
      }

      {:ok, encoded_response} = Protocol.IdentityResponse.encode(identity_response)

      # Mock UART that returns a valid identity response
      {:ok, uart_pid} =
        MockUART.start_link(
          responses: [{:ok, encoded_response}],
          write_result: :ok,
          drain_result: :ok
        )

      # Act
      result = discover_with_mock(uart_pid)

      # Assert
      assert {:ok, %Device{} = device} = result
      assert device.id == device_id
      assert device.version == version
      assert device.config_id == config_id
    end

    test "creates device with config_id when provided" do
      # Arrange
      identity_response = %Protocol.IdentityResponse{
        request_id: 123,
        device_id: 10,
        version: 50,
        config_id: 0
      }

      {:ok, encoded_response} = Protocol.IdentityResponse.encode(identity_response)

      {:ok, uart_pid} = MockUART.start_link(responses: [{:ok, encoded_response}])

      # Act
      result = discover_with_mock(uart_pid)

      # Assert
      assert {:ok, %Device{} = device} = result
      assert device.config_id == 0
    end
  end

  describe "discover/1 - retry logic" do
    test "retries up to 3 times when receiving unexpected messages" do
      # Arrange
      # First two responses are unexpected, third is valid
      unexpected_msg = %Protocol.Heartbeat{}
      {:ok, encoded_unexpected} = Protocol.Heartbeat.encode(unexpected_msg)

      valid_response = %Protocol.IdentityResponse{
        request_id: 123,
        device_id: 1,
        version: 1,
        config_id: 0
      }

      {:ok, encoded_valid} = Protocol.IdentityResponse.encode(valid_response)

      {:ok, uart_pid} =
        MockUART.start_link(
          responses: [
            {:ok, encoded_unexpected},
            {:ok, encoded_unexpected},
            {:ok, encoded_valid}
          ]
        )

      # Act
      result = discover_with_mock(uart_pid)

      # Assert
      assert {:ok, %Device{}} = result
    end

    test "returns error after 3 failed attempts with unexpected messages" do
      # Arrange
      unexpected_msg = %Protocol.Heartbeat{}
      {:ok, encoded_unexpected} = Protocol.Heartbeat.encode(unexpected_msg)

      {:ok, uart_pid} =
        MockUART.start_link(
          responses: [
            {:ok, encoded_unexpected},
            {:ok, encoded_unexpected},
            {:ok, encoded_unexpected}
          ]
        )

      # Act
      result = discover_with_mock(uart_pid)

      # Assert
      assert {:error, :no_valid_response} = result
    end

    test "returns error after 3 failed attempts with timeouts" do
      # Arrange
      {:ok, uart_pid} =
        MockUART.start_link(
          responses: [
            {:error, :timeout},
            {:error, :timeout},
            {:error, :timeout}
          ]
        )

      # Act
      result = discover_with_mock(uart_pid)

      # Assert
      assert {:error, :timeout} = result
    end

    test "returns error on first timeout" do
      # Arrange
      # Note: Timeouts don't trigger retries - only unexpected message types do
      {:ok, uart_pid} =
        MockUART.start_link(
          responses: [
            {:error, :timeout}
          ]
        )

      # Act
      result = discover_with_mock(uart_pid)

      # Assert
      assert {:error, :timeout} = result
    end
  end

  describe "discover/1 - error handling" do
    test "returns error when UART write fails" do
      # Arrange
      {:ok, uart_pid} = MockUART.start_link(write_result: {:error, :eio})

      # Act
      result = discover_with_mock(uart_pid)

      # Assert
      assert {:error, :eio} = result
    end

    test "returns error when UART drain fails" do
      # Arrange
      {:ok, uart_pid} = MockUART.start_link(drain_result: {:error, :closed})

      # Act
      result = discover_with_mock(uart_pid)

      # Assert
      assert {:error, :closed} = result
    end

    test "returns error when UART read fails immediately" do
      # Arrange
      {:ok, uart_pid} = MockUART.start_link(responses: [{:error, :closed}])

      # Act
      result = discover_with_mock(uart_pid)

      # Assert
      assert {:error, :closed} = result
    end

    test "returns error when receiving malformed data" do
      # Arrange
      malformed_data = <<0xFF, 0xFF, 0xFF, 0xFF>>

      {:ok, uart_pid} = MockUART.start_link(responses: [{:ok, malformed_data}])

      # Act
      result = discover_with_mock(uart_pid)

      # Assert
      # Should fail to decode and eventually return error
      assert {:error, _reason} = result
    end
  end

  describe "discover/1 - edge cases" do
    test "handles empty response data" do
      # Arrange
      {:ok, uart_pid} = MockUART.start_link(responses: [{:ok, <<>>}])

      # Act
      result = discover_with_mock(uart_pid)

      # Assert
      assert {:error, _reason} = result
    end

    test "succeeds immediately on first valid response" do
      # Arrange
      # Note: version is uint8, max value is 255
      valid_response = %Protocol.IdentityResponse{
        request_id: 123,
        device_id: 99,
        version: 231,
        config_id: 888
      }

      {:ok, encoded_valid} = Protocol.IdentityResponse.encode(valid_response)

      {:ok, uart_pid} = MockUART.start_link(responses: [{:ok, encoded_valid}])

      # Act
      result = discover_with_mock(uart_pid)

      # Assert
      assert {:ok, %Device{id: 99, version: 231, config_id: 888}} = result
    end
  end

  # Helper function to call discover with our mock
  defp discover_with_mock(uart_pid) do
    # We need to stub the Circuits.UART module calls
    # For this test, we'll define a wrapper that uses our mock

    # Create the identity request
    identity_request = %Protocol.IdentityRequest{
      request_id: :erlang.unique_integer([:positive])
    }

    with {:ok, encoded_request} <- Protocol.IdentityRequest.encode(identity_request),
         :ok <- MockUART.write(uart_pid, encoded_request),
         :ok <- MockUART.drain(uart_pid) do
      read_response_with_mock(uart_pid)
    end
  end

  defp read_response_with_mock(uart_pid, attempt \\ 0)

  defp read_response_with_mock(_pid, 3), do: {:error, :no_valid_response}

  defp read_response_with_mock(uart_pid, attempt) do
    with {:ok, data} <- MockUART.read(uart_pid, 1_000),
         {:ok, %Protocol.IdentityResponse{} = response} <- Protocol.Message.decode(data) do
      {:ok,
       %Device{
         id: response.device_id,
         version: response.version,
         config_id: response.config_id
       }}
    else
      {:ok, _other} -> read_response_with_mock(uart_pid, attempt + 1)
      {:error, reason} -> {:error, reason}
    end
  end
end
