defmodule TswIo.Train.Calibration.LeverSessionTest do
  use TswIo.DataCase, async: false
  use Mimic

  alias TswIo.Train.Calibration.LeverSession
  alias TswIo.Train.Calibration.SessionSupervisor
  alias TswIo.Simulator.Client
  alias TswIo.Train

  setup :verify_on_exit!
  setup :set_mimic_global

  setup do
    # Create a train and element for testing with unique identifier
    {:ok, train} =
      Train.create_train(%{
        name: "Test Train",
        identifier: "Test_Train_#{System.unique_integer([:positive])}"
      })

    {:ok, element} =
      Train.create_element(train.id, %{
        name: "Throttle",
        type: :lever
      })

    {:ok, lever_config} =
      Train.create_lever_config(element.id, %{
        min_endpoint: "Throttle.Min",
        max_endpoint: "Throttle.Max",
        value_endpoint: "Throttle.Value",
        notch_count_endpoint: "Throttle.NotchCount",
        notch_index_endpoint: "Throttle.NotchIndex"
      })

    client = Client.new("http://localhost:8080", "test-key")

    # Clean up any running session for this lever config
    on_exit(fn ->
      if pid = LeverSession.whereis(lever_config.id) do
        try do
          GenServer.stop(pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    %{train: train, element: element, lever_config: lever_config, client: client}
  end

  describe "single notch calibration" do
    test "creates a single linear notch spanning full range", %{
      lever_config: lever_config,
      client: client
    } do
      # Stub all Client functions to catch any unmocked calls
      stub(Client, :get_float, fn _client, path ->
        case path do
          "Throttle.Min" -> {:ok, 0.0}
          "Throttle.Max" -> {:ok, 1.0}
          _ -> {:ok, 0.0}
        end
      end)

      stub(Client, :get_int, fn _client, path ->
        case path do
          "Throttle.NotchCount" -> {:ok, 1}
          _ -> {:ok, 0}
        end
      end)

      stub(Client, :set, fn _client, _path, _value -> {:ok, %{}} end)
      stub(Client, :get_string, fn _client, _path -> {:ok, ""} end)
      stub(Client, :get, fn _client, _path -> {:ok, %{}} end)
      stub(Client, :list, fn _client, _path -> {:ok, []} end)

      # Subscribe to calibration events
      LeverSession.subscribe(lever_config.id)

      # Start the calibration
      {:ok, _pid} = SessionSupervisor.start_calibration(client, lever_config)

      # Wait for result
      assert_receive {:calibration_result, {:ok, updated_config}}, 5000

      # Verify the notches - force fresh load from DB
      config_with_notches = TswIo.Repo.preload(updated_config, :notches, force: true)

      assert length(config_with_notches.notches) == 1

      [notch] = config_with_notches.notches
      assert notch.type == :linear
      assert notch.index == 0
      assert notch.min_value == 0.0
      assert notch.max_value == 1.0
      assert notch.description == "Notch 0"
      assert notch.value == nil
    end
  end

  describe "multiple gate notches calibration" do
    test "detects gate notches with correct values", %{
      lever_config: lever_config,
      client: client
    } do
      # Use atomics to track the last set value (multiplied by 1000 for precision)
      set_value_ref = :atomics.new(1, signed: true)
      :atomics.put(set_value_ref, 1, 0)

      stub(Client, :get_float, fn _client, path ->
        case path do
          "Throttle.Min" ->
            {:ok, 0.0}

          "Throttle.Max" ->
            {:ok, 1.0}

          "Throttle.Value" ->
            # Gate behavior: snap to 0.0, 0.5, or 1.0 based on set value
            set_val = :atomics.get(set_value_ref, 1) / 1000

            snapped =
              cond do
                set_val < 0.25 -> 0.0
                set_val < 0.75 -> 0.5
                true -> 1.0
              end

            {:ok, snapped}
        end
      end)

      stub(Client, :get_int, fn _client, path ->
        case path do
          "Throttle.NotchCount" ->
            {:ok, 3}

          "Throttle.NotchIndex" ->
            set_val = :atomics.get(set_value_ref, 1) / 1000

            notch_index =
              cond do
                set_val < 0.25 -> 0
                set_val < 0.75 -> 1
                true -> 2
              end

            {:ok, notch_index}
        end
      end)

      stub(Client, :set, fn _client, "Throttle.Value", value ->
        :atomics.put(set_value_ref, 1, round(value * 1000))
        {:ok, %{}}
      end)

      # Subscribe and start
      LeverSession.subscribe(lever_config.id)
      {:ok, _pid} = SessionSupervisor.start_calibration(client, lever_config)

      # Wait for result
      assert_receive {:calibration_result, {:ok, updated_config}}, 10_000

      # Verify the notches
      config_with_notches = TswIo.Repo.preload(updated_config, :notches)
      notches = Enum.sort_by(config_with_notches.notches, & &1.index)

      assert length(notches) == 3

      # All should be gate notches with the snapped values
      [notch0, notch1, notch2] = notches

      assert notch0.type == :gate
      assert notch0.index == 0
      assert notch0.value == 0.0
      assert notch0.description == "Notch 0"

      assert notch1.type == :gate
      assert notch1.index == 1
      assert notch1.value == 0.5
      assert notch1.description == "Notch 1"

      assert notch2.type == :gate
      assert notch2.index == 2
      assert notch2.value == 1.0
      assert notch2.description == "Notch 2"
    end
  end

  describe "linear notches calibration" do
    test "detects linear notches when values are accepted as-is", %{
      lever_config: lever_config,
      client: client
    } do
      # Use atomics to track the last set value
      set_value_ref = :atomics.new(1, signed: true)
      :atomics.put(set_value_ref, 1, 0)

      stub(Client, :get_float, fn _client, path ->
        case path do
          "Throttle.Min" ->
            {:ok, 0.0}

          "Throttle.Max" ->
            {:ok, 1.0}

          "Throttle.Value" ->
            # Linear: return exactly what was set
            value = :atomics.get(set_value_ref, 1) / 1000
            {:ok, value}
        end
      end)

      stub(Client, :get_int, fn _client, path ->
        case path do
          "Throttle.NotchCount" ->
            {:ok, 2}

          "Throttle.NotchIndex" ->
            # Notch changes at 0.5
            set_val = :atomics.get(set_value_ref, 1) / 1000

            if set_val < 0.5 do
              {:ok, 0}
            else
              {:ok, 1}
            end
        end
      end)

      stub(Client, :set, fn _client, "Throttle.Value", value ->
        :atomics.put(set_value_ref, 1, round(value * 1000))
        {:ok, %{}}
      end)

      # Subscribe and start
      LeverSession.subscribe(lever_config.id)
      {:ok, _pid} = SessionSupervisor.start_calibration(client, lever_config)

      # Wait for result
      assert_receive {:calibration_result, {:ok, updated_config}}, 10_000

      # Verify the notches
      config_with_notches = TswIo.Repo.preload(updated_config, :notches)
      notches = Enum.sort_by(config_with_notches.notches, & &1.index)

      assert length(notches) == 2

      [notch0, notch1] = notches

      assert notch0.type == :linear
      assert notch0.index == 0
      assert notch0.value == nil
      assert notch0.min_value != nil
      assert notch0.max_value != nil
      assert notch0.description == "Notch 0"

      assert notch1.type == :linear
      assert notch1.index == 1
      assert notch1.description == "Notch 1"
    end
  end

  describe "progress broadcasts" do
    test "broadcasts progress during calibration", %{
      lever_config: lever_config,
      client: client
    } do
      set_value_ref = :atomics.new(1, signed: true)
      :atomics.put(set_value_ref, 1, 0)

      stub(Client, :get_float, fn _client, path ->
        case path do
          "Throttle.Min" ->
            {:ok, 0.0}

          "Throttle.Max" ->
            {:ok, 1.0}

          "Throttle.Value" ->
            set_val = :atomics.get(set_value_ref, 1) / 1000
            snapped = if set_val < 0.5, do: 0.0, else: 1.0
            {:ok, snapped}
        end
      end)

      stub(Client, :get_int, fn _client, path ->
        case path do
          "Throttle.NotchCount" ->
            {:ok, 2}

          "Throttle.NotchIndex" ->
            set_val = :atomics.get(set_value_ref, 1) / 1000
            if set_val < 0.5, do: {:ok, 0}, else: {:ok, 1}
        end
      end)

      stub(Client, :set, fn _client, "Throttle.Value", value ->
        :atomics.put(set_value_ref, 1, round(value * 1000))
        {:ok, %{}}
      end)

      # Subscribe and start
      LeverSession.subscribe(lever_config.id)
      {:ok, _pid} = SessionSupervisor.start_calibration(client, lever_config)

      # Should receive at least one progress update
      assert_receive {:calibration_progress, progress_state}, 5000
      assert is_map(progress_state)
      assert Map.has_key?(progress_state, :progress)
      assert Map.has_key?(progress_state, :step)
      assert progress_state.lever_config_id == lever_config.id

      # Eventually receive the result
      assert_receive {:calibration_result, {:ok, _}}, 10_000
    end
  end

  describe "error handling" do
    test "handles API errors gracefully", %{
      lever_config: lever_config,
      client: client
    } do
      # Mock API error on min endpoint
      stub(Client, :get_float, fn _client, _path ->
        {:error, :connection_refused}
      end)

      # Subscribe and start
      LeverSession.subscribe(lever_config.id)
      {:ok, _pid} = SessionSupervisor.start_calibration(client, lever_config)

      # Should receive error result
      assert_receive {:calibration_result, {:error, :connection_refused}}, 5000
    end

    test "returns error when already running", %{
      lever_config: lever_config,
      client: client
    } do
      set_value_ref = :atomics.new(1, signed: true)
      :atomics.put(set_value_ref, 1, 0)

      stub(Client, :get_float, fn _client, path ->
        case path do
          "Throttle.Min" -> {:ok, 0.0}
          "Throttle.Max" -> {:ok, 1.0}
          "Throttle.Value" -> {:ok, 0.0}
        end
      end)

      stub(Client, :get_int, fn _client, path ->
        case path do
          "Throttle.NotchCount" -> {:ok, 100}
          "Throttle.NotchIndex" -> {:ok, 0}
        end
      end)

      # Keep it running by making API calls slow
      stub(Client, :set, fn _client, "Throttle.Value", _value ->
        Process.sleep(100)
        {:ok, %{}}
      end)

      {:ok, _pid} = SessionSupervisor.start_calibration(client, lever_config)

      # Give it time to start
      Process.sleep(50)

      # Try to start another - should fail
      assert {:error, :already_running} =
               SessionSupervisor.start_calibration(client, lever_config)
    end
  end

  describe "session lookup" do
    test "whereis returns pid of running session", %{
      lever_config: lever_config,
      client: client
    } do
      stub(Client, :get_float, fn _client, path ->
        case path do
          "Throttle.Min" -> {:ok, 0.0}
          "Throttle.Max" -> {:ok, 1.0}
          "Throttle.Value" -> {:ok, 0.0}
        end
      end)

      stub(Client, :get_int, fn _client, path ->
        case path do
          "Throttle.NotchCount" -> {:ok, 100}
          "Throttle.NotchIndex" -> {:ok, 0}
        end
      end)

      stub(Client, :set, fn _client, "Throttle.Value", _value ->
        Process.sleep(50)
        {:ok, %{}}
      end)

      {:ok, pid} = SessionSupervisor.start_calibration(client, lever_config)

      # Give it time to start
      Process.sleep(50)

      assert LeverSession.whereis(lever_config.id) == pid
      assert SessionSupervisor.session_running?(lever_config.id) == true
    end

    test "whereis returns nil for non-existent session", %{lever_config: lever_config} do
      assert LeverSession.whereis(lever_config.id) == nil
      assert SessionSupervisor.session_running?(lever_config.id) == false
    end
  end

  describe "get_state/1" do
    test "returns current state during calibration", %{
      lever_config: lever_config,
      client: client
    } do
      stub(Client, :get_float, fn _client, path ->
        case path do
          "Throttle.Min" -> {:ok, 0.0}
          "Throttle.Max" -> {:ok, 1.0}
          "Throttle.Value" -> {:ok, 0.0}
        end
      end)

      stub(Client, :get_int, fn _client, path ->
        case path do
          "Throttle.NotchCount" -> {:ok, 100}
          "Throttle.NotchIndex" -> {:ok, 0}
        end
      end)

      stub(Client, :set, fn _client, "Throttle.Value", _value ->
        Process.sleep(50)
        {:ok, %{}}
      end)

      {:ok, _pid} = SessionSupervisor.start_calibration(client, lever_config)

      # Give it time to start calibrating
      Process.sleep(100)

      state = LeverSession.get_state(lever_config.id)

      assert state != nil
      assert state.lever_config.id == lever_config.id
      assert state.step == :calibrating
      assert state.min_value == 0.0
      assert state.max_value == 1.0
    end
  end
end
