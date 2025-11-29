defmodule TswIoWeb.ApiExplorerComponentTest do
  use TswIoWeb.ConnCase, async: false
  use Mimic

  import Phoenix.LiveViewTest

  alias TswIo.Simulator.Client
  alias TswIo.Simulator.ConnectionState
  alias TswIo.Simulator
  alias TswIo.Train, as: TrainContext

  setup :verify_on_exit!
  setup :set_mimic_global

  setup do
    # Create a train with an element and lever config
    {:ok, train} =
      TrainContext.create_train(%{
        name: "Test Train",
        identifier: "Test_Train_#{System.unique_integer([:positive])}"
      })

    {:ok, element} =
      TrainContext.create_element(train.id, %{
        name: "Throttle",
        type: :lever
      })

    {:ok, lever_config} =
      TrainContext.create_lever_config(element.id, %{
        min_endpoint: "Throttle.Min",
        max_endpoint: "Throttle.Max",
        value_endpoint: "Throttle.Value",
        notch_count_endpoint: "Throttle.NotchCount",
        notch_index_endpoint: "Throttle.NotchIndex"
      })

    # Reload train with all associations for tests
    {:ok, train} = TrainContext.get_train(train.id, preload: [elements: [lever_config: :notches]])

    # Create a mock client
    client = Client.new("http://localhost:8080", "test-key")

    # Create a connected simulator status
    simulator_status =
      %ConnectionState{}
      |> ConnectionState.mark_connecting(client)
      |> ConnectionState.mark_connected(%{"version" => "1.0"})

    %{
      train: train,
      element: hd(train.elements),
      lever_config: lever_config,
      client: client,
      simulator_status: simulator_status
    }
  end

  # Helper to open the lever config modal and then the API explorer
  defp open_api_explorer(view, element, field) do
    # First open the lever config modal
    view
    |> element("button[phx-click='configure_lever'][phx-value-id='#{element.id}']")
    |> render_click()

    # Then open the API explorer
    view
    |> element("button[phx-click='open_api_explorer'][phx-value-field='#{field}']")
    |> render_click()
  end

  describe "component initialization" do
    test "loads root nodes on mount", %{
      conn: conn,
      train: train,
      element: element,
      client: client
    } do
      # Mock simulator to return connected status with client
      stub(Simulator, :get_status, fn ->
        %ConnectionState{status: :connected, client: client}
      end)

      # Mock Client.list to return root nodes
      stub(Client, :list, fn _client ->
        {:ok, %{"nodes" => ["ControlDesk", "Gauges", "Train"]}}
      end)

      {:ok, view, _html} = live(conn, ~p"/trains/#{train.id}")

      open_api_explorer(view, element, "min_endpoint")

      # The modal should be visible with root nodes
      html = render(view)
      assert html =~ "Browse Simulator API"
      assert html =~ "ControlDesk"
      assert html =~ "Gauges"
      assert html =~ "Train"
    end

    test "shows error when API list fails", %{
      conn: conn,
      train: train,
      element: element,
      client: client
    } do
      stub(Simulator, :get_status, fn ->
        %ConnectionState{status: :connected, client: client}
      end)

      stub(Client, :list, fn _client ->
        {:error, :connection_refused}
      end)

      {:ok, view, _html} = live(conn, ~p"/trains/#{train.id}")

      open_api_explorer(view, element, "min_endpoint")

      html = render(view)
      assert html =~ "Failed to load API nodes"
    end
  end

  describe "navigation" do
    test "navigates into folder nodes", %{
      conn: conn,
      train: train,
      element: element,
      client: client
    } do
      stub(Simulator, :get_status, fn ->
        %ConnectionState{status: :connected, client: client}
      end)

      # First call returns root nodes, second returns child nodes
      expect(Client, :list, fn _client ->
        {:ok, %{"nodes" => ["ControlDesk", "Gauges"]}}
      end)

      expect(Client, :list, fn _client, "ControlDesk" ->
        {:ok, %{"nodes" => ["Throttle", "Brake", "Reverser"]}}
      end)

      {:ok, view, _html} = live(conn, ~p"/trains/#{train.id}")

      open_api_explorer(view, element, "min_endpoint")

      # Click on ControlDesk to navigate into it
      view
      |> element("button[phx-click='navigate'][phx-value-node='ControlDesk']")
      |> render_click()

      html = render(view)
      # Should show child nodes
      assert html =~ "Throttle"
      assert html =~ "Brake"
      assert html =~ "Reverser"
      # Should show breadcrumb
      assert html =~ "ControlDesk"
    end

    test "navigates back via breadcrumb", %{
      conn: conn,
      train: train,
      element: element,
      client: client
    } do
      stub(Simulator, :get_status, fn ->
        %ConnectionState{status: :connected, client: client}
      end)

      expect(Client, :list, fn _client ->
        {:ok, %{"nodes" => ["ControlDesk"]}}
      end)

      expect(Client, :list, fn _client, "ControlDesk" ->
        {:ok, %{"nodes" => ["Throttle"]}}
      end)

      # Going back to root
      expect(Client, :list, fn _client ->
        {:ok, %{"nodes" => ["ControlDesk", "Gauges"]}}
      end)

      {:ok, view, _html} = live(conn, ~p"/trains/#{train.id}")

      open_api_explorer(view, element, "min_endpoint")

      # Navigate into ControlDesk
      view
      |> element("button[phx-click='navigate'][phx-value-node='ControlDesk']")
      |> render_click()

      # Go back to root via home button
      view
      |> element("button[phx-click='go_back'][phx-value-index='0']")
      |> render_click()

      html = render(view)
      assert html =~ "ControlDesk"
      assert html =~ "Gauges"
    end

    test "shows leaf node preview when navigating to endpoint", %{
      conn: conn,
      train: train,
      element: element,
      client: client
    } do
      stub(Simulator, :get_status, fn ->
        %ConnectionState{status: :connected, client: client}
      end)

      expect(Client, :list, fn _client ->
        {:ok, %{"nodes" => ["Value"]}}
      end)

      # Navigating to Value fails list (it's a leaf), so we try get
      expect(Client, :list, fn _client, "Value" ->
        {:error, :not_a_directory}
      end)

      expect(Client, :get, fn _client, "Value" ->
        {:ok, %{"value" => 0.75}}
      end)

      {:ok, view, _html} = live(conn, ~p"/trains/#{train.id}")

      open_api_explorer(view, element, "min_endpoint")

      view
      |> element("button[phx-click='navigate'][phx-value-node='Value']")
      |> render_click()

      html = render(view)
      assert html =~ "Preview"
      assert html =~ "0.75"
    end
  end

  describe "search filtering" do
    test "filters nodes by search term", %{
      conn: conn,
      train: train,
      element: element,
      client: client
    } do
      stub(Simulator, :get_status, fn ->
        %ConnectionState{status: :connected, client: client}
      end)

      stub(Client, :list, fn _client ->
        {:ok, %{"nodes" => ["Throttle", "ThrottleMin", "ThrottleMax", "Brake", "Reverser"]}}
      end)

      {:ok, view, _html} = live(conn, ~p"/trains/#{train.id}")

      open_api_explorer(view, element, "min_endpoint")

      # Initially all nodes visible
      html = render(view)
      assert html =~ "Throttle"
      assert html =~ "Brake"

      # Search for "Throttle"
      view
      |> element("input[phx-keyup='search']")
      |> render_keyup(%{"search" => "Throttle"})

      html = render(view)
      assert html =~ "Throttle"
      assert html =~ "ThrottleMin"
      assert html =~ "ThrottleMax"
      refute html =~ ">Brake<"
      refute html =~ ">Reverser<"
    end

    test "search is case insensitive", %{
      conn: conn,
      train: train,
      element: element,
      client: client
    } do
      stub(Simulator, :get_status, fn ->
        %ConnectionState{status: :connected, client: client}
      end)

      stub(Client, :list, fn _client ->
        {:ok, %{"nodes" => ["ThrottleNode", "BRAKE", "reverser"]}}
      end)

      {:ok, view, _html} = live(conn, ~p"/trains/#{train.id}")

      open_api_explorer(view, element, "min_endpoint")

      view
      |> element("input[phx-keyup='search']")
      |> render_keyup(%{"search" => "brake"})

      html = render(view)
      assert html =~ "BRAKE"
      # ThrottleNode should be filtered out when searching for "brake"
      refute html =~ "ThrottleNode"
    end
  end

  describe "preview functionality" do
    test "previews node value without navigating", %{
      conn: conn,
      train: train,
      element: element,
      client: client
    } do
      stub(Simulator, :get_status, fn ->
        %ConnectionState{status: :connected, client: client}
      end)

      stub(Client, :list, fn _client ->
        {:ok, %{"nodes" => ["ThrottleValue", "BrakeValue"]}}
      end)

      expect(Client, :get, fn _client, "ThrottleValue" ->
        {:ok, %{"value" => 0.5, "unit" => "normalized"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/trains/#{train.id}")

      open_api_explorer(view, element, "min_endpoint")

      # Click preview button (eye icon)
      view
      |> element("button[phx-click='preview'][phx-value-node='ThrottleValue']")
      |> render_click()

      html = render(view)
      assert html =~ "Preview"
      assert html =~ "ThrottleValue"
      assert html =~ "0.5"
      # Nodes should still be visible (didn't navigate away)
      assert html =~ "BrakeValue"
    end
  end

  describe "path selection" do
    test "selecting path sends event to parent and closes explorer", %{
      conn: conn,
      train: train,
      element: element,
      client: client
    } do
      stub(Simulator, :get_status, fn ->
        %ConnectionState{status: :connected, client: client}
      end)

      stub(Client, :list, fn _client ->
        {:ok, %{"nodes" => ["Throttle.Min", "Throttle.Max"]}}
      end)

      {:ok, view, _html} = live(conn, ~p"/trains/#{train.id}")

      open_api_explorer(view, element, "min_endpoint")

      # Select a path
      view
      |> element("button[phx-click='select'][phx-value-path='Throttle.Min']")
      |> render_click()

      html = render(view)

      # Explorer should be closed
      refute html =~ "Browse Simulator API"

      # The form field should be updated with the selected path
      # (lever config modal should still be open with the updated value)
      assert html =~ "Throttle.Min"
    end

    test "selecting path from preview", %{
      conn: conn,
      train: train,
      element: element,
      client: client
    } do
      stub(Simulator, :get_status, fn ->
        %ConnectionState{status: :connected, client: client}
      end)

      stub(Client, :list, fn _client ->
        {:ok, %{"nodes" => ["Throttle.Value"]}}
      end)

      expect(Client, :get, fn _client, "Throttle.Value" ->
        {:ok, %{"value" => 0.75}}
      end)

      {:ok, view, _html} = live(conn, ~p"/trains/#{train.id}")

      open_api_explorer(view, element, "value_endpoint")

      # Preview the value
      view
      |> element("button[phx-click='preview'][phx-value-node='Throttle.Value']")
      |> render_click()

      # Select from preview panel (the btn-primary "Select This Path" button)
      view
      |> element("button.btn-primary[phx-click='select'][phx-value-path='Throttle.Value']")
      |> render_click()

      html = render(view)
      refute html =~ "Browse Simulator API"
    end
  end

  describe "closing the explorer" do
    test "closes on backdrop click", %{
      conn: conn,
      train: train,
      element: element,
      client: client
    } do
      stub(Simulator, :get_status, fn ->
        %ConnectionState{status: :connected, client: client}
      end)

      stub(Client, :list, fn _client ->
        {:ok, %{"nodes" => ["Node1"]}}
      end)

      {:ok, view, _html} = live(conn, ~p"/trains/#{train.id}")

      open_api_explorer(view, element, "min_endpoint")

      assert render(view) =~ "Browse Simulator API"

      # Click the backdrop to close
      view
      |> element("div.bg-black\\/50[phx-click='close']")
      |> render_click()

      refute render(view) =~ "Browse Simulator API"
    end

    test "closes on X button click", %{
      conn: conn,
      train: train,
      element: element,
      client: client
    } do
      stub(Simulator, :get_status, fn ->
        %ConnectionState{status: :connected, client: client}
      end)

      stub(Client, :list, fn _client ->
        {:ok, %{"nodes" => ["Node1"]}}
      end)

      {:ok, view, _html} = live(conn, ~p"/trains/#{train.id}")

      open_api_explorer(view, element, "min_endpoint")

      assert render(view) =~ "Browse Simulator API"

      # Click the X button (btn-circle)
      view
      |> element("button.btn-circle[phx-click='close']")
      |> render_click()

      refute render(view) =~ "Browse Simulator API"
    end
  end

  describe "error handling" do
    test "shows error when navigating to inaccessible node", %{
      conn: conn,
      train: train,
      element: element,
      client: client
    } do
      stub(Simulator, :get_status, fn ->
        %ConnectionState{status: :connected, client: client}
      end)

      expect(Client, :list, fn _client ->
        {:ok, %{"nodes" => ["Protected"]}}
      end)

      # List fails
      expect(Client, :list, fn _client, "Protected" ->
        {:error, :access_denied}
      end)

      # Get also fails
      expect(Client, :get, fn _client, "Protected" ->
        {:error, :access_denied}
      end)

      {:ok, view, _html} = live(conn, ~p"/trains/#{train.id}")

      open_api_explorer(view, element, "min_endpoint")

      view
      |> element("button[phx-click='navigate'][phx-value-node='Protected']")
      |> render_click()

      html = render(view)
      assert html =~ "Failed to access"
    end

    test "browse buttons are disabled when simulator not connected", %{
      conn: conn,
      train: train,
      element: element
    } do
      stub(Simulator, :get_status, fn ->
        %ConnectionState{status: :disconnected, client: nil}
      end)

      {:ok, view, _html} = live(conn, ~p"/trains/#{train.id}")

      # First open the lever config modal
      view
      |> element("button[phx-click='configure_lever'][phx-value-id='#{element.id}']")
      |> render_click()

      # The browse button should be disabled when simulator is not connected
      html = render(view)
      assert html =~ "disabled"
      # The explorer should not be shown
      refute html =~ "Browse Simulator API"
    end
  end

  describe "node icons" do
    test "shows correct icons for different node types", %{
      conn: conn,
      train: train,
      element: element,
      client: client
    } do
      stub(Simulator, :get_status, fn ->
        %ConnectionState{status: :connected, client: client}
      end)

      stub(Client, :list, fn _client ->
        {:ok,
         %{
           "nodes" => [
             "Folder",
             "Document.Value",
             "Function(param)"
           ]
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/trains/#{train.id}")

      open_api_explorer(view, element, "min_endpoint")

      html = render(view)
      # Folder icon for plain names
      assert html =~ "hero-folder"
      # Document icon for names with dots
      assert html =~ "hero-document"
      # Cube icon for function-like names with parentheses
      assert html =~ "hero-cube"
    end
  end
end
