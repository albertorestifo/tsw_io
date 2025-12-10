defmodule TswIo.Serial.Protocol.IdentityResponse do
  alias TswIo.Serial.Protocol.Message

  @behaviour Message

  @type t() :: %__MODULE__{
          request_id: integer(),
          version: String.t(),
          config_id: integer()
        }

  defstruct [:request_id, :version, :config_id]

  @impl Message
  def type(), do: 0x01

  @impl Message
  def encode(%__MODULE__{
        request_id: request_id,
        version: version,
        config_id: config_id
      }) do
    {major, minor, patch} = parse_version(version)

    {:ok,
     <<0x01, request_id::little-32-unsigned, major::8-unsigned, minor::8-unsigned,
       patch::8-unsigned, config_id::little-32-unsigned>>}
  end

  @impl Message
  def decode(
        <<0x01, request_id::little-32-unsigned, major::8-unsigned, minor::8-unsigned,
          patch::8-unsigned, config_id::little-32-unsigned>>
      ) do
    {:ok,
     %__MODULE__{
       request_id: request_id,
       version: "#{major}.#{minor}.#{patch}",
       config_id: config_id
     }}
  end

  @impl Message
  def decode(_) do
    {:error, :invalid_message}
  end

  defp parse_version(version) when is_binary(version) do
    [major, minor, patch] =
      version
      |> String.split(".")
      |> Enum.map(&String.to_integer/1)

    {major, minor, patch}
  end
end
