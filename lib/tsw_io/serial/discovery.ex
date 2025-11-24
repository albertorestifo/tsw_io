defmodule TswIo.Serial.Discovery do
  @moduledoc """
  Handles device discovery protocol over serial UART connections.

  Sends an identity request to a device and waits for a response.
  Retries up to 3 times if unexpected messages are received.

  Returns `{:ok, Device.t()}` if a device responds with valid identity,
  or `{:error, reason}` if discovery fails.
  """

  alias Circuits.UART
  alias TswIo.Device
  alias TswIo.Serial.Protocol

  @spec discover(pid()) :: {:ok, Device.t()} | {:error, term()}
  def discover(uart_pid) do
    identity_request = %Protocol.IdentityRequest{request_id: :erlang.unique_integer([:positive])}

    with {:ok, encoded_request} <- Protocol.IdentityRequest.encode(identity_request),
         :ok <- UART.write(uart_pid, encoded_request),
         :ok <- UART.drain(uart_pid) do
      read_response(uart_pid)
    end
  end

  @spec read_response(pid(), non_neg_integer()) :: {:ok, Device.t()} | {:error, term()}
  defp read_response(uart_pid, attempt \\ 0)

  defp read_response(_pid, 3), do: {:error, :no_valid_response}

  defp read_response(uart_pid, attempt) do
    with {:ok, data} <- UART.read(uart_pid, 1_000),
         {:ok, %Protocol.IdentityResponse{} = response} <- Protocol.Message.decode(data) do
      {:ok,
       %Device{id: response.device_id, version: response.version, config_id: response.config_id}}
    else
      {:ok, _other} -> read_response(uart_pid, attempt + 1)
      {:error, reason} -> {:error, reason}
    end
  end
end
