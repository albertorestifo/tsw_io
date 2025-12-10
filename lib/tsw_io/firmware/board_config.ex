defmodule TswIo.Firmware.BoardConfig do
  @moduledoc """
  Board-specific configuration for avrdude uploads.

  Defines all supported Arduino board types and their corresponding
  avrdude parameters (MCU, programmer, baud rate, etc.).
  """

  @type board_type ::
          :uno
          | :nano
          | :nano_old_bootloader
          | :leonardo
          | :micro
          | :mega2560
          | :sparkfun_pro_micro

  @type config :: %{
          name: String.t(),
          mcu: String.t(),
          programmer: String.t(),
          baud_rate: pos_integer(),
          hex_filename: String.t()
        }

  @configs %{
    uno: %{
      name: "Arduino Uno",
      mcu: "m328p",
      programmer: "arduino",
      baud_rate: 115_200,
      hex_filename: "tws-io-arduino-uno.hex"
    },
    nano: %{
      name: "Arduino Nano",
      mcu: "m328p",
      programmer: "arduino",
      baud_rate: 57_600,
      hex_filename: "tws-io-arduino-nano.hex"
    },
    nano_old_bootloader: %{
      name: "Arduino Nano (Old Bootloader)",
      mcu: "m328p",
      programmer: "arduino",
      baud_rate: 57_600,
      hex_filename: "tws-io-arduino-nano-old-bootloader.hex"
    },
    leonardo: %{
      name: "Arduino Leonardo",
      mcu: "m32u4",
      programmer: "avr109",
      baud_rate: 57_600,
      hex_filename: "tws-io-arduino-leonardo.hex"
    },
    micro: %{
      name: "Arduino Micro",
      mcu: "m32u4",
      programmer: "avr109",
      baud_rate: 57_600,
      hex_filename: "tws-io-arduino-micro.hex"
    },
    mega2560: %{
      name: "Arduino Mega 2560",
      mcu: "m2560",
      programmer: "wiring",
      baud_rate: 115_200,
      hex_filename: "tws-io-arduino-mega-2560.hex"
    },
    sparkfun_pro_micro: %{
      name: "SparkFun Pro Micro",
      mcu: "m32u4",
      programmer: "avr109",
      baud_rate: 57_600,
      hex_filename: "tws-io-sparkfun-pro-micro.hex"
    }
  }

  @doc """
  Returns a list of all supported board types.
  Used for Ecto.Enum values.
  """
  @spec board_types() :: [board_type()]
  def board_types, do: Map.keys(@configs)

  @doc """
  Returns the configuration for a specific board type.
  """
  @spec get_config(board_type()) :: {:ok, config()} | {:error, :unknown_board}
  def get_config(board_type) when is_atom(board_type) do
    case Map.fetch(@configs, board_type) do
      {:ok, config} -> {:ok, config}
      :error -> {:error, :unknown_board}
    end
  end

  @doc """
  Returns the configuration for a specific board type, raising on error.
  """
  @spec get_config!(board_type()) :: config()
  def get_config!(board_type) when is_atom(board_type) do
    case get_config(board_type) do
      {:ok, config} -> config
      {:error, :unknown_board} -> raise ArgumentError, "Unknown board type: #{board_type}"
    end
  end

  @doc """
  Returns all board configurations as a list of {type, config} tuples.
  Useful for populating UI dropdowns.
  """
  @spec all_configs() :: [{board_type(), config()}]
  def all_configs, do: Enum.to_list(@configs)

  @doc """
  Returns board options formatted for use in Phoenix form select inputs.
  """
  @spec select_options() :: [{String.t(), board_type()}]
  def select_options do
    @configs
    |> Enum.map(fn {type, config} -> {config.name, type} end)
    |> Enum.sort_by(fn {name, _} -> name end)
  end

  @doc """
  Detects the board type from a GitHub release asset filename.

  ## Examples

      iex> BoardConfig.detect_board_type("tws-io-arduino-uno.hex")
      {:ok, :uno}

      iex> BoardConfig.detect_board_type("unknown.hex")
      :error
  """
  @spec detect_board_type(String.t()) :: {:ok, board_type()} | :error
  def detect_board_type(filename) when is_binary(filename) do
    Enum.find_value(@configs, :error, fn {type, config} ->
      if config.hex_filename == filename do
        {:ok, type}
      end
    end)
  end
end
