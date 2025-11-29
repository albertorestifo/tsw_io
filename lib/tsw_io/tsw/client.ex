defmodule TswIo.Tsw.Client do
  @moduledoc """
  Client for the Train Sim World 6 External Interface API.

  The client allows external applications to read real-time simulation data
  and control train cab elements via JSON over HTTP.

  ## Setup

  Create a client with the base URL and API key:

      client = TswIo.Tsw.Client.new("http://localhost:31270", "your-api-key")

  The API key is read from `CommAPIKey.txt` in the game's config directory.

  ## Usage

      # Get current speed
      {:ok, response} = TswIo.Tsw.Client.get(client, "CurrentDrivableActor.Function.HUD_GetSpeed")

      # Set throttle position
      {:ok, response} = TswIo.Tsw.Client.set(client, "CurrentDrivableActor/Throttle(Lever).InputValue", 0.5)

      # List available controls
      {:ok, nodes} = TswIo.Tsw.Client.list(client, "CurrentDrivableActor")
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

      iex> client = TswIo.Tsw.Client.new("http://localhost:31270", "your-api-key")
      %TswIo.Tsw.Client{base_url: "http://localhost:31270", api_key: "your-api-key", ...}

  """
  @spec new(String.t(), String.t()) :: t()
  def new(base_url, api_key) when is_binary(base_url) and is_binary(api_key) do
    req =
      Req.new(
        base_url: base_url,
        headers: [{"DTGCommKey", api_key}]
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
      {:ok, nodes} = TswIo.Tsw.Client.list(client)

      # List nodes under a specific path
      {:ok, nodes} = TswIo.Tsw.Client.list(client, "CurrentDrivableActor")

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
        TswIo.Tsw.Client.get(client, "CurrentDrivableActor.Function.HUD_GetSpeed")

      # Get throttle notch position
      {:ok, response} = TswIo.Tsw.Client.get(
        client,
        "CurrentDrivableActor/Throttle(Lever).Function.GetCurrentNotchIndex"
      )

  """
  @spec get(t(), String.t()) :: {:ok, response()} | error()
  def get(%__MODULE__{} = client, path) when is_binary(path) do
    request(client, :get, "/get/#{path}")
  end

  @doc """
  Writes a value to the specified path and endpoint.

  The path format is: `node_path.endpoint`

  ## Examples

      # Set throttle position
      {:ok, %{"Result" => "Success"}} =
        TswIo.Tsw.Client.set(client, "CurrentDrivableActor/Throttle(Lever).InputValue", 0.25)

      # Set weather cloudiness
      {:ok, response} = TswIo.Tsw.Client.set(client, "WeatherManager.Cloudiness", 0.5)

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

      {:ok, response} = TswIo.Tsw.Client.subscribe(
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

      {:ok, %{"Entries" => entries}} = TswIo.Tsw.Client.get_subscription(client, 1)

  """
  @spec get_subscription(t(), integer()) :: {:ok, response()} | error()
  def get_subscription(%__MODULE__{} = client, subscription_id)
      when is_integer(subscription_id) do
    request(client, :get, "/subscription", params: [Subscription: subscription_id])
  end

  @doc """
  Removes a subscription.

  ## Examples

      {:ok, response} = TswIo.Tsw.Client.unsubscribe(client, 1)

  """
  @spec unsubscribe(t(), integer()) :: {:ok, response()} | error()
  def unsubscribe(%__MODULE__{} = client, subscription_id) when is_integer(subscription_id) do
    request(client, :delete, "/subscription", params: [Subscription: subscription_id])
  end

  @doc """
  Lists all active subscriptions.

  ## Examples

      {:ok, subscriptions} = TswIo.Tsw.Client.list_subscriptions(client)

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
