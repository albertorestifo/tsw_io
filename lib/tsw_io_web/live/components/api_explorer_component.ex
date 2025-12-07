defmodule TswIoWeb.ApiExplorerComponent do
  @moduledoc """
  LiveComponent for browsing the TSW simulator API.

  Provides hierarchical navigation through the simulator's API tree,
  allowing users to browse, search, preview values, and select paths.

  ## Usage

      <.live_component
        module={TswIoWeb.ApiExplorerComponent}
        id="api-explorer"
        field={:min_endpoint}
        client={@simulator_client}
      />

  ## Events sent to parent

  - `{:api_explorer_select, field, path}` - When user selects a path
  - `{:api_explorer_close}` - When user closes the explorer
  """

  use TswIoWeb, :live_component

  alias TswIo.Simulator.Client

  @impl true
  def update(%{client: %Client{} = client, field: field}, socket) do
    socket =
      socket
      |> assign(:field, field)
      |> assign(:client, client)

    # Initialize on first mount
    socket =
      if socket.assigns[:initialized] do
        socket
      else
        initialize_explorer(socket)
      end

    {:ok, socket}
  end

  def update(assigns, socket) do
    # Handle updates without client (shouldn't happen, but be safe)
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("navigate", %{"node" => node}, socket) do
    %{client: client, path: path, search: search} = socket.assigns

    new_path = path ++ [node]
    full_path = Enum.join(new_path, "/")

    # Set loading state
    socket = assign(socket, :loading, true)
    socket = assign(socket, :error, nil)

    # Fetch child nodes
    case Client.list(client, full_path) do
      {:ok, %{"Nodes" => nodes}} ->
        node_names = extract_node_names(nodes)
        sorted_nodes = Enum.sort(node_names)

        {:noreply,
         socket
         |> assign(:path, new_path)
         |> assign(:nodes, sorted_nodes)
         |> assign(:filtered_nodes, filter_nodes(sorted_nodes, search))
         |> assign(:loading, false)
         |> assign(:preview, nil)}

      {:ok, _response} ->
        # Response without Nodes - might be a leaf node, try to get its value
        case Client.get(client, full_path) do
          {:ok, response} ->
            {:noreply,
             socket
             |> assign(:loading, false)
             |> assign(:preview, %{path: full_path, value: response})}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:loading, false)
             |> assign(:error, "Failed to access: #{inspect(reason)}")}
        end

      {:error, _reason} ->
        # This might be a leaf node (endpoint), try to get its value
        case Client.get(client, full_path) do
          {:ok, response} ->
            {:noreply,
             socket
             |> assign(:loading, false)
             |> assign(:preview, %{path: full_path, value: response})}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:loading, false)
             |> assign(:error, "Failed to access: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("go_back", %{"index" => index_str}, socket) do
    %{client: client, search: search} = socket.assigns

    index = String.to_integer(index_str)
    new_path = Enum.take(socket.assigns.path, index)

    # Set loading state
    socket =
      socket
      |> assign(:loading, true)
      |> assign(:error, nil)
      |> assign(:preview, nil)

    # Fetch nodes at this path
    result =
      if new_path == [] do
        Client.list(client)
      else
        Client.list(client, Enum.join(new_path, "/"))
      end

    case result do
      {:ok, %{"Nodes" => nodes}} ->
        node_names = extract_node_names(nodes)
        sorted_nodes = Enum.sort(node_names)

        {:noreply,
         socket
         |> assign(:path, new_path)
         |> assign(:nodes, sorted_nodes)
         |> assign(:filtered_nodes, filter_nodes(sorted_nodes, search))
         |> assign(:loading, false)}

      {:ok, _response} ->
        # Unexpected response format
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:error, "Unexpected response format from API")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:error, "Failed to navigate: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("search", %{"value" => search}, socket) do
    filtered = filter_nodes(socket.assigns.nodes, search)

    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:filtered_nodes, filtered)}
  end

  @impl true
  def handle_event("preview", %{"node" => node}, socket) do
    %{client: client, path: path} = socket.assigns

    full_path =
      case path do
        [] -> node
        segments -> Enum.join(segments, "/") <> "/" <> node
      end

    case Client.get(client, full_path) do
      {:ok, response} ->
        {:noreply, assign(socket, :preview, %{path: full_path, value: response})}

      {:error, _reason} ->
        # Not a readable endpoint, just ignore
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select", %{"path" => path}, socket) do
    send(self(), {:api_explorer_select, socket.assigns.field, path})
    {:noreply, socket}
  end

  @impl true
  def handle_event("close", _params, socket) do
    send(self(), {:api_explorer_close})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    full_path = Enum.join(assigns.path, "/")
    assigns = assign(assigns, :full_path, full_path)

    ~H"""
    <div class="fixed inset-0 z-[60] flex items-center justify-center p-4">
      <div class="absolute inset-0 bg-black/50" phx-click="close" phx-target={@myself} />
      <div class="relative bg-base-100 rounded-xl shadow-xl w-full max-w-2xl max-h-[85vh] flex flex-col">
        <div class="p-4 border-b border-base-300">
          <div class="flex items-center justify-between mb-3">
            <h2 class="text-lg font-semibold">Browse Simulator API</h2>
            <button
              type="button"
              phx-click="close"
              phx-target={@myself}
              class="btn btn-ghost btn-sm btn-circle"
            >
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          </div>

          <div class="flex items-center gap-2 text-sm">
            <button
              type="button"
              phx-click="go_back"
              phx-value-index="0"
              phx-target={@myself}
              class="btn btn-ghost btn-xs"
            >
              <.icon name="hero-home" class="w-4 h-4" />
            </button>
            <span :for={{segment, index} <- Enum.with_index(@path)} class="flex items-center">
              <span class="text-base-content/40">/</span>
              <button
                type="button"
                phx-click="go_back"
                phx-value-index={index + 1}
                phx-target={@myself}
                class="btn btn-ghost btn-xs"
              >
                {segment}
              </button>
            </span>
          </div>

          <div class="mt-3">
            <input
              type="text"
              placeholder="Search nodes..."
              value={@search}
              phx-keyup="search"
              phx-target={@myself}
              phx-debounce="150"
              class="input input-bordered input-sm w-full"
            />
          </div>
        </div>

        <div class="flex-1 overflow-y-auto p-4">
          <div :if={@error} class="alert alert-error mb-4">
            <.icon name="hero-exclamation-circle" class="w-5 h-5" />
            <span>{@error}</span>
          </div>

          <div :if={@loading} class="flex justify-center py-8">
            <span class="loading loading-spinner loading-lg" />
          </div>

          <div
            :if={not @loading and Enum.empty?(@filtered_nodes)}
            class="text-center py-8 text-base-content/50"
          >
            <.icon name="hero-folder-open" class="w-12 h-12 mx-auto mb-2 opacity-30" />
            <p class="text-sm">No nodes found</p>
          </div>

          <div :if={not @loading and not Enum.empty?(@filtered_nodes)} class="space-y-1">
            <div :for={node <- @filtered_nodes} class="group">
              <div class="flex items-center gap-2 p-2 rounded-lg hover:bg-base-200 transition-colors">
                <button
                  type="button"
                  phx-click="navigate"
                  phx-value-node={node}
                  phx-target={@myself}
                  class="flex-1 flex items-center gap-2 text-left"
                >
                  <.icon name={node_icon(node)} class="w-4 h-4 text-base-content/50" />
                  <span class="font-mono text-sm truncate">{node}</span>
                </button>
                <button
                  type="button"
                  phx-click="preview"
                  phx-value-node={node}
                  phx-target={@myself}
                  class="btn btn-ghost btn-xs opacity-0 group-hover:opacity-100 transition-opacity"
                  title="Preview value"
                >
                  <.icon name="hero-eye" class="w-4 h-4" />
                </button>
                <button
                  type="button"
                  phx-click="select"
                  phx-value-path={if @full_path == "", do: node, else: "#{@full_path}/#{node}"}
                  phx-target={@myself}
                  class="btn btn-ghost btn-xs text-primary opacity-0 group-hover:opacity-100 transition-opacity"
                  title="Select this path"
                >
                  <.icon name="hero-check" class="w-4 h-4" />
                </button>
              </div>
            </div>
          </div>
        </div>

        <div :if={@preview} class="border-t border-base-300 p-4 bg-base-200/50">
          <div class="flex items-center justify-between mb-2">
            <h3 class="text-sm font-semibold">Preview</h3>
            <span class="font-mono text-xs text-base-content/60">{@preview.path}</span>
          </div>
          <pre class="bg-base-300 rounded-lg p-3 text-xs font-mono overflow-x-auto max-h-32">{format_preview(@preview.value)}</pre>
          <div class="mt-3 flex justify-end">
            <button
              type="button"
              phx-click="select"
              phx-value-path={@preview.path}
              phx-target={@myself}
              class="btn btn-primary btn-sm"
            >
              <.icon name="hero-check" class="w-4 h-4" /> Select This Path
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Private functions

  defp initialize_explorer(socket) do
    case Client.list(socket.assigns.client) do
      {:ok, %{"Nodes" => nodes}} ->
        node_names = extract_node_names(nodes)
        sorted_nodes = Enum.sort(node_names)

        socket
        |> assign(:path, [])
        |> assign(:nodes, sorted_nodes)
        |> assign(:filtered_nodes, sorted_nodes)
        |> assign(:search, "")
        |> assign(:loading, false)
        |> assign(:error, nil)
        |> assign(:preview, nil)
        |> assign(:initialized, true)

      {:ok, _response} ->
        # Unexpected response format (no Nodes key)
        socket
        |> assign(:path, [])
        |> assign(:nodes, [])
        |> assign(:filtered_nodes, [])
        |> assign(:search, "")
        |> assign(:loading, false)
        |> assign(:error, "Unexpected response format from API")
        |> assign(:preview, nil)
        |> assign(:initialized, true)

      {:error, reason} ->
        socket
        |> assign(:path, [])
        |> assign(:nodes, [])
        |> assign(:filtered_nodes, [])
        |> assign(:search, "")
        |> assign(:loading, false)
        |> assign(:error, "Failed to load API nodes: #{inspect(reason)}")
        |> assign(:preview, nil)
        |> assign(:initialized, true)
    end
  end

  # Extracts node names from the API response format
  # Root level uses "NodeName", child levels use "Name"
  @spec extract_node_names([map()]) :: [String.t()]
  defp extract_node_names(nodes) do
    Enum.map(nodes, fn node ->
      Map.get(node, "NodeName") || Map.get(node, "Name", "")
    end)
  end

  @spec filter_nodes([String.t()], String.t()) :: [String.t()]
  defp filter_nodes(nodes, ""), do: nodes

  defp filter_nodes(nodes, search) do
    search_lower = String.downcase(search)

    Enum.filter(nodes, fn node ->
      String.contains?(String.downcase(node), search_lower)
    end)
  end

  @spec node_icon(String.t()) :: String.t()
  defp node_icon(node) do
    cond do
      String.contains?(node, "(") -> "hero-cube"
      String.contains?(node, ".") -> "hero-document"
      true -> "hero-folder"
    end
  end

  defp format_preview(value) when is_map(value) do
    Jason.encode!(value, pretty: true)
  end

  defp format_preview(value), do: inspect(value, pretty: true)
end
