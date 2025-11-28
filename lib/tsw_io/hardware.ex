defmodule TswIo.Hardware do
  @moduledoc """
  Context for hardware device configurations and management.
  """

  import Ecto.Query

  alias TswIo.Repo
  alias TswIo.Hardware.{Device, Input}
  alias TswIo.Hardware.Input.Calibration
  alias TswIo.Hardware.Calibration.{Calculator, SessionSupervisor}

  # Delegate configuration operations to ConfigurationManager
  defdelegate apply_configuration(port, device_id), to: TswIo.Hardware.ConfigurationManager
  defdelegate subscribe_configuration(), to: TswIo.Hardware.ConfigurationManager
  defdelegate subscribe_input_values(port), to: TswIo.Hardware.ConfigurationManager
  defdelegate get_input_values(port), to: TswIo.Hardware.ConfigurationManager

  # Device operations

  @doc """
  Get a device by ID.

  ## Options

    * `:preload` - List of associations to preload (default: [])

  ## Examples

      iex> get_device(123)
      {:ok, %Device{}}

      iex> get_device(999)
      {:error, :not_found}

  """
  @spec get_device(integer(), keyword()) :: {:ok, Device.t()} | {:error, :not_found}
  def get_device(id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    case Repo.get(Device, id) do
      nil -> {:error, :not_found}
      device -> {:ok, Repo.preload(device, preloads)}
    end
  end

  @doc """
  Get a device by config_id.

  The config_id is the stable link between a physical device and its configuration
  in the database. It's stored on the device and returned in IdentityResponse.
  """
  @spec get_device_by_config_id(integer()) :: {:ok, Device.t()} | {:error, :not_found}
  def get_device_by_config_id(config_id) do
    case Repo.get_by(Device, config_id: config_id) do
      nil -> {:error, :not_found}
      device -> {:ok, Repo.preload(device, :inputs)}
    end
  end

  @doc """
  Create a new device.
  """
  @spec create_device(map()) :: {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def create_device(attrs \\ %{}) do
    %Device{}
    |> Device.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a device.
  """
  @spec update_device(Device.t(), map()) :: {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def update_device(%Device{} = device, attrs) do
    device
    |> Device.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Update device with config_id after successful configuration.

  This is called by the ConfigurationManager when a ConfigurationStored
  message is received from the device.
  """
  @spec confirm_configuration(integer(), integer()) :: {:ok, Device.t()} | {:error, term()}
  def confirm_configuration(device_id, config_id) do
    with {:ok, device} <- get_device(device_id) do
      device
      |> Device.changeset(%{config_id: config_id})
      |> Repo.update()
    end
  end

  @doc """
  Generate a unique configuration ID.

  Uses :erlang.unique_integer to generate a unique, monotonically increasing ID.
  """
  @spec generate_config_id() :: {:ok, integer()}
  def generate_config_id do
    {:ok, :erlang.unique_integer([:positive, :monotonic])}
  end

  # Input operations

  @doc """
  List all inputs for a device, ordered by pin.
  """
  @spec list_inputs(integer()) :: {:ok, [Input.t()]}
  def list_inputs(device_id) do
    inputs =
      Input
      |> where([i], i.device_id == ^device_id)
      |> order_by([i], i.pin)
      |> Repo.all()

    {:ok, inputs}
  end

  @doc """
  Create an input for a device.
  """
  @spec create_input(integer(), map()) :: {:ok, Input.t()} | {:error, Ecto.Changeset.t()}
  def create_input(device_id, attrs) do
    %Input{device_id: device_id}
    |> Input.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Delete an input by ID or Input struct.
  """
  @spec delete_input(integer() | Input.t()) ::
          {:ok, Input.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def delete_input(input_id) when is_integer(input_id) do
    case Repo.get(Input, input_id) do
      nil -> {:error, :not_found}
      input -> Repo.delete(input)
    end
  end

  def delete_input(%Input{} = input) do
    Repo.delete(input)
  end

  @doc """
  Get an input by ID.

  ## Options

    * `:preload` - List of associations to preload (default: [])
  """
  @spec get_input(integer(), keyword()) :: {:ok, Input.t()} | {:error, :not_found}
  def get_input(id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    case Repo.get(Input, id) do
      nil -> {:error, :not_found}
      input -> {:ok, Repo.preload(input, preloads)}
    end
  end

  # Calibration operations

  @doc """
  Start a calibration session for an input.

  ## Options

    * `:max_hardware_value` - Optional. Hardware max value (default: 1023).

  Returns `{:ok, pid}` on success.
  """
  @spec start_calibration_session(Input.t(), String.t(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def start_calibration_session(%Input{} = input, port, opts \\ []) do
    session_opts =
      Keyword.merge(opts,
        input_id: input.id,
        port: port,
        pin: input.pin
      )

    SessionSupervisor.start_session(session_opts)
  end

  @doc """
  Save calibration data for an input.

  Creates or updates the calibration for the given input.
  """
  @spec save_calibration(integer(), map()) ::
          {:ok, Calibration.t()} | {:error, Ecto.Changeset.t()}
  def save_calibration(input_id, attrs) do
    attrs_with_input = Map.put(attrs, :input_id, input_id)

    case Repo.get_by(Calibration, input_id: input_id) do
      nil ->
        %Calibration{}
        |> Calibration.changeset(attrs_with_input)
        |> Repo.insert()

      existing ->
        existing
        |> Calibration.changeset(attrs_with_input)
        |> Repo.update()
    end
  end

  @doc """
  Normalize a raw input value using its calibration.

  Returns the normalized value (0 to total_travel).
  """
  @spec normalize_value(integer(), Calibration.t()) :: integer()
  defdelegate normalize_value(raw_value, calibration), to: Calculator, as: :normalize

  @doc """
  Get the total travel range for a calibration.
  """
  @spec total_travel(Calibration.t()) :: integer()
  defdelegate total_travel(calibration), to: Calculator
end
