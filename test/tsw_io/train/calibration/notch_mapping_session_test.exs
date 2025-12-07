defmodule TswIo.Train.Calibration.NotchMappingSessionTest do
  use TswIo.DataCase, async: false

  alias TswIo.Hardware
  alias TswIo.Train
  alias TswIo.Train.Calibration.NotchMappingSession

  # Helper to create test fixtures
  defp create_fixtures(_context) do
    # Create hardware device and input with calibration
    {:ok, device} = Hardware.create_device(%{name: "Test Device"})

    {:ok, input} =
      Hardware.create_input(device.id, %{pin: 5, input_type: :analog, sensitivity: 5})

    {:ok, _calibration} =
      Hardware.save_calibration(input.id, %{
        min_value: 100,
        max_value: 900,
        max_hardware_value: 1023,
        is_inverted: false,
        has_rollover: false
      })

    # Reload input with calibration
    {:ok, input} = Hardware.get_input(input.id, preload: [:calibration])

    # Create train with lever config and notches
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

    # Add notches - mix of gate and linear types
    {:ok, lever_config} =
      Train.save_notches(lever_config, [
        %{type: :gate, value: -1.0, description: "Reverse"},
        %{type: :linear, min_value: 0.0, max_value: 0.5, description: "Low"},
        %{type: :gate, value: 1.0, description: "Full"}
      ])

    %{
      device: device,
      input: input,
      train: train,
      element: element,
      lever_config: lever_config,
      calibration: input.calibration
    }
  end

  defp start_session(%{lever_config: lever_config, calibration: calibration}) do
    {:ok, pid} =
      NotchMappingSession.start_link(
        lever_config: lever_config,
        port: "/dev/test",
        pin: 5,
        calibration: calibration
      )

    pid
  end

  describe "session initialization" do
    setup [:create_fixtures]

    test "starts with :ready step", context do
      pid = start_session(context)

      state = NotchMappingSession.get_public_state(pid)
      assert state.current_step == :ready
      assert state.lever_config_id == context.lever_config.id

      NotchMappingSession.cancel(pid)
    end

    test "calculates correct notch count", context do
      pid = start_session(context)

      state = NotchMappingSession.get_public_state(pid)
      assert state.notch_count == 3

      NotchMappingSession.cancel(pid)
    end

    test "initializes captured_ranges with nils", context do
      pid = start_session(context)

      state = NotchMappingSession.get_public_state(pid)
      assert state.captured_ranges == [nil, nil, nil]

      NotchMappingSession.cancel(pid)
    end

    test "extracts notch info including type", context do
      pid = start_session(context)

      state = NotchMappingSession.get_public_state(pid)
      notches = state.notches

      assert length(notches) == 3
      assert Enum.at(notches, 0).type == :gate
      assert Enum.at(notches, 0).description == "Reverse"
      assert Enum.at(notches, 1).type == :linear
      assert Enum.at(notches, 1).description == "Low"
      assert Enum.at(notches, 2).type == :gate
      assert Enum.at(notches, 2).description == "Full"

      NotchMappingSession.cancel(pid)
    end

    test "calculates total_travel from calibration", context do
      pid = start_session(context)

      state = NotchMappingSession.get_public_state(pid)
      # max_value (900) - min_value (100) = 800
      assert state.total_travel == 800

      NotchMappingSession.cancel(pid)
    end
  end

  describe "step progression" do
    setup [:create_fixtures]

    test "can start mapping from ready step", context do
      pid = start_session(context)

      assert :ok = NotchMappingSession.start_mapping(pid)

      state = NotchMappingSession.get_public_state(pid)
      assert state.current_step == {:mapping_notch, 0}
      assert state.current_notch.description == "Reverse"

      NotchMappingSession.cancel(pid)
    end

    test "cannot start mapping from non-ready step", context do
      pid = start_session(context)

      # Start mapping first
      assert :ok = NotchMappingSession.start_mapping(pid)

      # Try to start again
      assert {:error, :invalid_step} = NotchMappingSession.start_mapping(pid)

      NotchMappingSession.cancel(pid)
    end

    test "cannot capture range without enough samples", context do
      pid = start_session(context)

      assert :ok = NotchMappingSession.start_mapping(pid)

      # Try to capture without any samples
      assert {:error, :not_enough_samples} = NotchMappingSession.capture_range(pid)

      NotchMappingSession.cancel(pid)
    end

    test "cannot capture range without movement (min == max)", context do
      pid = start_session(context)

      assert :ok = NotchMappingSession.start_mapping(pid)

      # Send 10 samples all with same value
      for _ <- 1..10 do
        send(pid, {:input_value_updated, "/dev/test", 5, 500})
      end

      :timer.sleep(20)

      # Should fail because min == max (no range detected)
      assert {:error, :no_range_detected} = NotchMappingSession.capture_range(pid)

      NotchMappingSession.cancel(pid)
    end

    test "can capture range with varied samples", context do
      pid = start_session(context)

      assert :ok = NotchMappingSession.start_mapping(pid)

      # Send varied samples to create a range
      # Raw values 200-300 → calibrated 100-200
      for value <- [200, 220, 250, 280, 300, 250, 220, 280, 240, 260] do
        send(pid, {:input_value_updated, "/dev/test", 5, value})
      end

      :timer.sleep(20)

      # Should be able to capture now
      assert :ok = NotchMappingSession.capture_range(pid)

      state = NotchMappingSession.get_public_state(pid)
      # Should have moved to notch 1
      assert state.current_step == {:mapping_notch, 1}
      # First notch range should be captured
      assert hd(state.captured_ranges) != nil
      assert hd(state.captured_ranges).min == 100
      assert hd(state.captured_ranges).max == 200

      NotchMappingSession.cancel(pid)
    end

    test "progresses through all notches to preview", context do
      pid = start_session(context)

      assert :ok = NotchMappingSession.start_mapping(pid)

      # Capture all 3 notch ranges (need at least 10 samples each with range)
      ranges = [
        # Notch 0: raw 200-300 → calibrated 100-200
        [200, 220, 240, 260, 280, 300, 250, 230, 270, 290],
        # Notch 1: raw 400-600 → calibrated 300-500
        [400, 440, 480, 520, 560, 600, 500, 450, 550, 580],
        # Notch 2: raw 700-850 → calibrated 600-750
        [700, 720, 750, 780, 810, 850, 800, 760, 830, 790]
      ]

      for range_values <- ranges do
        for value <- range_values do
          send(pid, {:input_value_updated, "/dev/test", 5, value})
        end

        :timer.sleep(20)
        assert :ok = NotchMappingSession.capture_range(pid)
      end

      state = NotchMappingSession.get_public_state(pid)
      assert state.current_step == :preview
      assert state.all_captured == true

      NotchMappingSession.cancel(pid)
    end
  end

  describe "sample collection" do
    setup [:create_fixtures]

    test "tracks current value and min/max from input", context do
      pid = start_session(context)

      assert :ok = NotchMappingSession.start_mapping(pid)

      # Send a few samples
      send(pid, {:input_value_updated, "/dev/test", 5, 500})
      :timer.sleep(10)

      state = NotchMappingSession.get_public_state(pid)
      # Raw 500 → calibrated 400 (500 - 100 min_value)
      assert state.current_value == 400
      assert state.current_min == 400
      assert state.current_max == 400

      # Send higher value
      send(pid, {:input_value_updated, "/dev/test", 5, 600})
      :timer.sleep(10)

      state = NotchMappingSession.get_public_state(pid)
      assert state.current_value == 500
      assert state.current_min == 400
      assert state.current_max == 500

      NotchMappingSession.cancel(pid)
    end

    test "ignores samples from other pins", context do
      pid = start_session(context)

      assert :ok = NotchMappingSession.start_mapping(pid)

      # Send sample for different pin
      send(pid, {:input_value_updated, "/dev/test", 6, 500})
      :timer.sleep(10)

      state = NotchMappingSession.get_public_state(pid)
      assert state.sample_count == 0

      NotchMappingSession.cancel(pid)
    end

    test "tracks sample count", context do
      pid = start_session(context)

      assert :ok = NotchMappingSession.start_mapping(pid)

      for i <- 1..5 do
        send(pid, {:input_value_updated, "/dev/test", 5, 500 + i})
        :timer.sleep(5)

        state = NotchMappingSession.get_public_state(pid)
        assert state.sample_count == i
      end

      NotchMappingSession.cancel(pid)
    end

    test "can reset samples to start fresh", context do
      pid = start_session(context)

      assert :ok = NotchMappingSession.start_mapping(pid)

      # Collect some samples
      for value <- [200, 300, 400, 500, 600] do
        send(pid, {:input_value_updated, "/dev/test", 5, value})
      end

      :timer.sleep(20)

      state = NotchMappingSession.get_public_state(pid)
      assert state.sample_count == 5
      assert state.current_min == 100
      assert state.current_max == 500

      # Reset
      assert :ok = NotchMappingSession.reset_samples(pid)

      state = NotchMappingSession.get_public_state(pid)
      assert state.sample_count == 0
      assert state.current_min == nil
      assert state.current_max == nil

      NotchMappingSession.cancel(pid)
    end
  end

  describe "notch navigation" do
    setup [:create_fixtures]

    test "can go to specific notch", context do
      pid = start_session(context)

      assert :ok = NotchMappingSession.start_mapping(pid)

      # Jump to notch 2
      assert :ok = NotchMappingSession.go_to_notch(pid, 2)

      state = NotchMappingSession.get_public_state(pid)
      assert state.current_step == {:mapping_notch, 2}
      assert state.current_notch.description == "Full"

      NotchMappingSession.cancel(pid)
    end

    test "cannot go to invalid notch index", context do
      pid = start_session(context)

      assert :ok = NotchMappingSession.start_mapping(pid)

      # 3 notches means valid indices are 0-2
      assert {:error, :invalid_notch_index} = NotchMappingSession.go_to_notch(pid, 5)

      NotchMappingSession.cancel(pid)
    end

    test "can go back to edit previous notch", context do
      pid = start_session(context)

      assert :ok = NotchMappingSession.start_mapping(pid)

      # Capture notch 0
      for value <- [200, 220, 250, 280, 300, 250, 220, 280, 240, 260] do
        send(pid, {:input_value_updated, "/dev/test", 5, value})
      end

      :timer.sleep(20)
      assert :ok = NotchMappingSession.capture_range(pid)

      # Now at notch 1, go back to 0
      assert :ok = NotchMappingSession.go_to_notch(pid, 0)

      state = NotchMappingSession.get_public_state(pid)
      assert state.current_step == {:mapping_notch, 0}
      # Samples should be reset when navigating
      assert state.sample_count == 0

      NotchMappingSession.cancel(pid)
    end
  end

  describe "preview and save" do
    setup [:create_fixtures]

    test "cannot go to preview without all ranges captured", context do
      pid = start_session(context)

      assert :ok = NotchMappingSession.start_mapping(pid)

      # Only capture one notch
      for value <- [200, 220, 250, 280, 300, 250, 220, 280, 240, 260] do
        send(pid, {:input_value_updated, "/dev/test", 5, value})
      end

      :timer.sleep(20)
      assert :ok = NotchMappingSession.capture_range(pid)

      # Try to go to preview
      assert {:error, :incomplete_ranges} = NotchMappingSession.go_to_preview(pid)

      NotchMappingSession.cancel(pid)
    end

    test "can go to preview with all ranges captured", context do
      pid = start_session(context)

      # Allow database access for the session process
      Ecto.Adapters.SQL.Sandbox.allow(TswIo.Repo, self(), pid)

      assert :ok = NotchMappingSession.start_mapping(pid)

      # Capture all 3 notch ranges (need at least 10 samples each)
      ranges = [
        [200, 220, 240, 260, 280, 300, 250, 230, 270, 290],
        [400, 440, 480, 520, 560, 600, 500, 450, 550, 580],
        [700, 720, 750, 780, 810, 850, 800, 760, 830, 790]
      ]

      for range_values <- ranges do
        for value <- range_values do
          send(pid, {:input_value_updated, "/dev/test", 5, value})
        end

        :timer.sleep(20)
        assert :ok = NotchMappingSession.capture_range(pid)
      end

      state = NotchMappingSession.get_public_state(pid)
      assert state.current_step == :preview

      NotchMappingSession.cancel(pid)
    end

    test "saves notch input ranges on save", context do
      pid = start_session(context)

      # Allow database access for the session process
      Ecto.Adapters.SQL.Sandbox.allow(TswIo.Repo, self(), pid)

      assert :ok = NotchMappingSession.start_mapping(pid)

      # Capture all 3 notch ranges (need at least 10 samples each)
      ranges = [
        [200, 220, 240, 260, 280, 300, 250, 230, 270, 290],
        [400, 440, 480, 520, 560, 600, 500, 450, 550, 580],
        [700, 720, 750, 780, 810, 850, 800, 760, 830, 790]
      ]

      for range_values <- ranges do
        for value <- range_values do
          send(pid, {:input_value_updated, "/dev/test", 5, value})
        end

        :timer.sleep(20)
        assert :ok = NotchMappingSession.capture_range(pid)
      end

      # Now in preview, save
      assert :ok = NotchMappingSession.save_mapping(pid)

      state = NotchMappingSession.get_public_state(pid)
      assert state.current_step == :complete
      assert match?({:ok, _}, state.result)

      # Verify notches were updated in database
      {:ok, updated_config} = Train.get_lever_config(context.element.id)
      notches = Enum.sort_by(updated_config.notches, & &1.index)

      # Each notch should have input ranges set (normalized to 0.0-1.0)
      assert Enum.all?(notches, fn notch ->
               notch.input_min != nil and notch.input_max != nil
             end)

      # Verify ranges are in 0.0-1.0 normalized format
      first_notch = hd(notches)
      # Calibrated 100-200 out of 800 total → 0.125-0.25
      assert first_notch.input_min >= 0.0 and first_notch.input_min <= 1.0
      assert first_notch.input_max >= 0.0 and first_notch.input_max <= 1.0
    end
  end

  describe "PubSub events" do
    setup [:create_fixtures]

    test "broadcasts session_started on init", context do
      NotchMappingSession.subscribe(context.lever_config.id)

      pid = start_session(context)

      assert_receive {:session_started, state}
      assert state.lever_config_id == context.lever_config.id
      assert state.current_step == :ready

      NotchMappingSession.cancel(pid)
    end

    test "broadcasts step_changed on step transitions", context do
      NotchMappingSession.subscribe(context.lever_config.id)

      pid = start_session(context)

      # Clear session_started
      assert_receive {:session_started, _}

      NotchMappingSession.start_mapping(pid)
      assert_receive {:step_changed, state}
      assert state.current_step == {:mapping_notch, 0}

      NotchMappingSession.cancel(pid)
    end

    test "broadcasts sample_updated on input values", context do
      NotchMappingSession.subscribe(context.lever_config.id)

      pid = start_session(context)

      # Clear session_started
      assert_receive {:session_started, _}

      NotchMappingSession.start_mapping(pid)
      assert_receive {:step_changed, _}

      send(pid, {:input_value_updated, "/dev/test", 5, 500})
      assert_receive {:sample_updated, state}
      assert state.current_value == 400

      NotchMappingSession.cancel(pid)
    end

    test "broadcasts mapping_result on completion", context do
      NotchMappingSession.subscribe(context.lever_config.id)

      pid = start_session(context)

      # Allow database access
      Ecto.Adapters.SQL.Sandbox.allow(TswIo.Repo, self(), pid)

      # Clear initial messages
      flush_mailbox()

      NotchMappingSession.start_mapping(pid)
      flush_mailbox()

      # Capture all notch ranges (need at least 10 samples each)
      ranges = [
        [200, 220, 240, 260, 280, 300, 250, 230, 270, 290],
        [400, 440, 480, 520, 560, 600, 500, 450, 550, 580],
        [700, 720, 750, 780, 810, 850, 800, 760, 830, 790]
      ]

      for range_values <- ranges do
        for value <- range_values do
          send(pid, {:input_value_updated, "/dev/test", 5, value})
        end

        :timer.sleep(20)
        NotchMappingSession.capture_range(pid)
        flush_mailbox()
      end

      # Save
      NotchMappingSession.save_mapping(pid)

      assert_receive {:mapping_result, {:ok, _updated_config}}, 1000
    end
  end

  describe "cancellation" do
    setup [:create_fixtures]

    test "cancel stops the session", context do
      pid = start_session(context)

      assert Process.alive?(pid)

      NotchMappingSession.cancel(pid)
      :timer.sleep(10)

      refute Process.alive?(pid)
    end
  end

  # Helper to flush all messages from mailbox
  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
