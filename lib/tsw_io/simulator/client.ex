defmodule TswIo.Simulator.Client do
  @moduledoc """
  Client for the Train Sim World 6 External Interface API.

  The client allows external applications to read real-time simulation data
  and control train cab elements via JSON over HTTP.

  ## Setup

  Create a client with the base URL and API key:

      client = TswIo.Simulator.Client.new("http://localhost:31270", "your-api-key")

  The API key is read from `CommAPIKey.txt` in the game's config directory.

  ## Usage

      # Get current speed
      {:ok, response} = TswIo.Simulator.Client.get(client, "CurrentDrivableActor.Function.HUD_GetSpeed")

      # Set throttle position
      {:ok, response} = TswIo.Simulator.Client.set(client, "CurrentDrivableActor/Throttle(Lever).InputValue", 0.5)

      # List available controls
      {:ok, nodes} = TswIo.Simulator.Client.list(client, "CurrentDrivableActor")
  """

  defstruct [:base_url, :api_key, :req]

  @type t :: %__MODULE__{
          base_url: String.t(),
          api_key: String.t(),
          req: Req.Request.t()
        }

  @type response :: %{String.t() => any()}
  @type error :: {:error, :invalid_key | :invalid_path | :request_failed | term()}

  @doc """
  Creates a new TSW API client.

  ## Parameters

    * `base_url` - The base URL of the TSW API (e.g., "http://localhost:31270")
    * `api_key` - The API key from CommAPIKey.txt

  ## Examples

      iex> client = TswIo.Simulator.Client.new("http://localhost:31270", "your-api-key")
      %TswIo.Simulator.Client{base_url: "http://localhost:31270", api_key: "your-api-key", ...}

  """
  @spec new(String.t(), String.t()) :: t()
  def new(base_url, api_key) when is_binary(base_url) and is_binary(api_key) do
    req =
      Req.new(
        base_url: base_url,
        headers: [{"DTGCommKey", api_key}],
        # Enable connection pooling to avoid socket exhaustion during rapid requests
        pool_timeout: 5_000,
        receive_timeout: 10_000,
        # Reduce retry attempts and delays for faster failure detection
        retry: :transient,
        retry_delay: fn attempt -> 100 * attempt end,
        max_retries: 2
      )

    %__MODULE__{
      base_url: base_url,
      api_key: api_key,
      req: req
    }
  end

  @doc """
  Lists available API commands.

  Returns information about the available API endpoints.
  """
  @spec info(t()) :: {:ok, response()} | error()
  def info(%__MODULE__{} = client) do
    request(client, :get, "/info")
  end

  @doc """
  Lists all available nodes/paths or nodes under a specific path.

  ## Examples

      # List all root nodes
      {:ok, nodes} = TswIo.Simulator.Client.list(client)

      # List nodes under a specific path
      {:ok, nodes} = TswIo.Simulator.Client.list(client, "CurrentDrivableActor")

  """
  @spec list(t(), String.t() | nil) :: {:ok, response()} | error()
  def list(%__MODULE__{} = client, path \\ nil) do
    url =
      case path do
        nil -> "/list"
        path -> "/list/#{path}"
      end

    request(client, :get, url)
  end

  @doc """
  Reads a value from the specified path and endpoint.

  The path format is: `node_path.endpoint`

  ## Examples

      # Get current speed (returns meters/second)
      {:ok, %{"Result" => "Success", "Values" => %{"Speed (ms)" => 4.54}}} =
        TswIo.Simulator.Client.get(client, "CurrentDrivableActor.Function.HUD_GetSpeed")

      # Get throttle notch position
      {:ok, response} = TswIo.Simulator.Client.get(
        client,
        "CurrentDrivableActor/Throttle(Lever).Function.GetCurrentNotchIndex"
      )

  """
  @spec get(t(), String.t()) :: {:ok, response()} | error()
  def get(%__MODULE__{} = client, path) when is_binary(path) do
    request(client, :get, "/get/#{path}")
  end

  @doc """
  Gets a value from the specified path and extracts it as an integer.

  Returns the first value from the "Values" map, parsed as an integer.

  ## Examples

      {:ok, 5} = TswIo.Simulator.Client.get_int(client, "CurrentFormation.FormationLength")

  """
  @spec get_int(t(), String.t()) :: {:ok, integer()} | error()
  def get_int(%__MODULE__{} = client, path) when is_binary(path) do
    with {:ok, %{"Values" => values}} when map_size(values) > 0 <- get(client, path) do
      case Map.values(values) do
        [value | _] when is_integer(value) -> {:ok, value}
        [value | _] when is_float(value) -> {:ok, trunc(value)}
        [value | _] when is_binary(value) -> parse_int(value)
        _ -> {:error, :invalid_value}
      end
    else
      {:ok, _} -> {:error, :invalid_value}
      error -> error
    end
  end

  @doc """
  Gets a value from the specified path and extracts it as a float.

  Returns the first value from the "Values" map, parsed as a float.

  ## Examples

      {:ok, 4.54} = TswIo.Simulator.Client.get_float(client, "CurrentDrivableActor.Function.HUD_GetSpeed")

  """
  @spec get_float(t(), String.t()) :: {:ok, float()} | error()
  def get_float(%__MODULE__{} = client, path) when is_binary(path) do
    with {:ok, %{"Values" => values}} when map_size(values) > 0 <- get(client, path) do
      case Map.values(values) do
        [value | _] when is_float(value) -> {:ok, Float.round(value, 2)}
        [value | _] when is_integer(value) -> {:ok, Float.round(value * 1.0, 2)}
        [value | _] when is_binary(value) -> parse_float_rounded(value)
        _ -> {:error, :invalid_value}
      end
    else
      {:ok, _} -> {:error, :invalid_value}
      error -> error
    end
  end

  @doc """
  Gets a value from the specified path and extracts it as a string.

  Returns the first value from the "Values" map as a string.

  ## Examples

      {:ok, "BR_Class_66_DB"} = TswIo.Simulator.Client.get_string(client, "CurrentFormation/0.ObjectClass")

  """
  @spec get_string(t(), String.t()) :: {:ok, String.t()} | error()
  def get_string(%__MODULE__{} = client, path) when is_binary(path) do
    with {:ok, %{"Values" => values}} when map_size(values) > 0 <- get(client, path) do
      case Map.values(values) do
        [value | _] when is_binary(value) -> {:ok, value}
        [value | _] -> {:ok, to_string(value)}
        _ -> {:error, :invalid_value}
      end
    else
      {:ok, _} -> {:error, :invalid_value}
      error -> error
    end
  end

  defp parse_int(string) do
    case Integer.parse(string) do
      {value, ""} -> {:ok, value}
      _ -> {:error, :invalid_value}
    end
  end

  defp parse_float_rounded(string) do
    case Float.parse(string) do
      {value, ""} -> {:ok, Float.round(value, 2)}
      _ -> {:error, :invalid_value}
    end
  end

  @doc """
  Writes a value to the specified path and endpoint.

  The path format is: `node_path.endpoint`

  ## Examples

      # Set throttle position
      {:ok, %{"Result" => "Success"}} =
        TswIo.Simulator.Client.set(client, "CurrentDrivableActor/Throttle(Lever).InputValue", 0.25)

      # Set weather cloudiness
      {:ok, response} = TswIo.Simulator.Client.set(client, "WeatherManager.Cloudiness", 0.5)

  """
  @spec set(t(), String.t(), number() | String.t() | boolean()) :: {:ok, response()} | error()
  def set(%__MODULE__{} = client, path, value) when is_binary(path) do
    request(client, :patch, "/set/#{path}", params: [Value: value])
  end

  @doc """
  Creates a subscription for the specified path.

  Subscriptions allow efficient polling of multiple values in a single request.

  ## Parameters

    * `client` - The TSW API client
    * `path` - The path to subscribe to (e.g., "CurrentDrivableActor.Function.HUD_GetSpeed")
    * `subscription_id` - An integer ID to group subscriptions

  ## Examples

      {:ok, response} = TswIo.Simulator.Client.subscribe(
        client,
        "CurrentDrivableActor.Function.HUD_GetSpeed",
        1
      )

  """
  @spec subscribe(t(), String.t(), integer()) :: {:ok, response()} | error()
  def subscribe(%__MODULE__{} = client, path, subscription_id)
      when is_binary(path) and is_integer(subscription_id) do
    request(client, :post, "/subscription/#{path}", params: [Subscription: subscription_id])
  end

  @doc """
  Reads values from a subscription.

  ## Examples

      {:ok, %{"Entries" => entries}} = TswIo.Simulator.Client.get_subscription(client, 1)

  """
  @spec get_subscription(t(), integer()) :: {:ok, response()} | error()
  def get_subscription(%__MODULE__{} = client, subscription_id)
      when is_integer(subscription_id) do
    request(client, :get, "/subscription", params: [Subscription: subscription_id])
  end

  @doc """
  Removes a subscription.

  ## Examples

      {:ok, response} = TswIo.Simulator.Client.unsubscribe(client, 1)

  """
  @spec unsubscribe(t(), integer()) :: {:ok, response()} | error()
  def unsubscribe(%__MODULE__{} = client, subscription_id) when is_integer(subscription_id) do
    request(client, :delete, "/subscription", params: [Subscription: subscription_id])
  end

  @doc """
  Lists all active subscriptions.

  ## Examples

      {:ok, subscriptions} = TswIo.Simulator.Client.list_subscriptions(client)

  """
  @spec list_subscriptions(t()) :: {:ok, response()} | error()
  def list_subscriptions(%__MODULE__{} = client) do
    request(client, :get, "/listsubscriptions")
  end

  defp request(%__MODULE__{req: req}, method, url, opts \\ []) do
    params = Keyword.get(opts, :params, [])

    request_opts = [method: method, url: url]

    request_opts =
      if params != [] do
        Keyword.put(request_opts, :params, params)
      else
        request_opts
      end

    case Req.request(req, request_opts) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: 403, body: body}} ->
        {:error, {:invalid_key, body}}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end
end
