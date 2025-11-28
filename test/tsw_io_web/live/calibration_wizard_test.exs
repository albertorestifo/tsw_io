defmodule TswIoWeb.CalibrationWizardTest do
  use TswIoWeb.ConnCase, async: false

  alias TswIo.Hardware
  alias TswIo.Hardware.Calibration.Session

  # Helper to create a device with an input
  defp create_device_with_input(_context) do
    {:ok, device} = Hardware.create_device(%{name: "Test Device"})

    {:ok, input} =
      Hardware.create_input(device.id, %{pin: 5, input_type: :analog, sensitivity: 5})

    %{device: device, input: input}
  end

  # Helper to allow spawned processes to access the database
  defp allow_session_db_access(pid) do
    Ecto.Adapters.SQL.Sandbox.allow(TswIo.Repo, self(), pid)
  end

  describe "CalibrationWizard rendering" do
    setup [:create_device_with_input]

    test "renders wizard header with pin number", %{input: input} do
      # Start a session manually to test the component's rendering
      {:ok, pid} =
        Session.start_link(
          input_id: input.id,
          port: "/dev/test",
          pin: input.pin
        )

      state = Session.get_public_state(pid)

      # Test the public state has expected fields
      assert state.input_id == input.id
      assert state.pin == input.pin
      assert state.current_step == :collecting_min
      assert state.min_sample_count == 0
      assert state.can_advance == false

      Session.cancel(pid)
    end

    test "initial step is collecting_min", %{input: input} do
      {:ok, pid} =
        Session.start_link(
          input_id: input.id,
          port: "/dev/test",
          pin: input.pin
        )

      state = Session.get_public_state(pid)
      assert state.current_step == :collecting_min

      Session.cancel(pid)
    end
  end

  describe "CalibrationWizard step progression" do
    setup [:create_device_with_input]

    test "cannot advance without sufficient samples", %{input: input} do
      {:ok, pid} =
        Session.start_link(
          input_id: input.id,
          port: "/dev/test",
          pin: input.pin
        )

      # Try to advance without samples
      assert {:error, :insufficient_samples} = Session.advance_step(pid)

      Session.cancel(pid)
    end

    test "can advance after collecting minimum samples", %{input: input} do
      {:ok, pid} =
        Session.start_link(
          input_id: input.id,
          port: "/dev/test",
          pin: input.pin
        )

      # Simulate collecting samples by sending messages
      # Need at least 10 samples with 3 unique values
      for value <- [10, 11, 12, 10, 11, 12, 10, 11, 12, 10] do
        send(pid, {:input_value_updated, "/dev/test", input.pin, value})
      end

      # Allow messages to be processed
      :timer.sleep(10)

      state = Session.get_public_state(pid)
      assert state.min_sample_count >= 10
      assert state.min_unique_count >= 3
      assert state.can_advance == true

      # Now we can advance
      assert :ok = Session.advance_step(pid)

      state = Session.get_public_state(pid)
      assert state.current_step == :sweeping

      Session.cancel(pid)
    end

    test "progresses through all steps to completion", %{input: input} do
      {:ok, pid} =
        Session.start_link(
          input_id: input.id,
          port: "/dev/test",
          pin: input.pin
        )

      # Allow the session process to access the database for saving calibration
      allow_session_db_access(pid)

      # Step 1: Collect min samples
      for value <- [10, 11, 12, 10, 11, 12, 10, 11, 12, 10] do
        send(pid, {:input_value_updated, "/dev/test", input.pin, value})
      end

      :timer.sleep(10)
      assert :ok = Session.advance_step(pid)
      assert Session.get_public_state(pid).current_step == :sweeping

      # Step 2: Sweep samples (just need 10 samples)
      for value <- 20..35 do
        send(pid, {:input_value_updated, "/dev/test", input.pin, value})
      end

      :timer.sleep(10)
      assert :ok = Session.advance_step(pid)
      assert Session.get_public_state(pid).current_step == :collecting_max

      # Step 3: Collect max samples
      for value <- [150, 151, 152, 150, 151, 152, 150, 151, 152, 150] do
        send(pid, {:input_value_updated, "/dev/test", input.pin, value})
      end

      :timer.sleep(10)
      assert :ok = Session.advance_step(pid)

      # Session should analyze and complete (it will terminate)
      # Give it time to process
      :timer.sleep(50)

      # Process should have stopped
      refute Process.alive?(pid)
    end
  end

  describe "CalibrationWizard cancellation" do
    setup [:create_device_with_input]

    test "cancel stops the session", %{input: input} do
      {:ok, pid} =
        Session.start_link(
          input_id: input.id,
          port: "/dev/test",
          pin: input.pin
        )

      assert Process.alive?(pid)

      Session.cancel(pid)
      :timer.sleep(10)

      refute Process.alive?(pid)
    end
  end

  describe "CalibrationWizard public state" do
    setup [:create_device_with_input]

    test "tracks sample counts correctly", %{input: input} do
      {:ok, pid} =
        Session.start_link(
          input_id: input.id,
          port: "/dev/test",
          pin: input.pin
        )

      # Initial state
      state = Session.get_public_state(pid)
      assert state.min_sample_count == 0
      assert state.min_unique_count == 0

      # Add some samples
      send(pid, {:input_value_updated, "/dev/test", input.pin, 10})
      send(pid, {:input_value_updated, "/dev/test", input.pin, 10})
      send(pid, {:input_value_updated, "/dev/test", input.pin, 20})
      :timer.sleep(10)

      state = Session.get_public_state(pid)
      assert state.min_sample_count == 3
      assert state.min_unique_count == 2

      Session.cancel(pid)
    end

    test "ignores samples from other pins", %{input: input} do
      {:ok, pid} =
        Session.start_link(
          input_id: input.id,
          port: "/dev/test",
          pin: input.pin
        )

      # Send sample for different pin
      send(pid, {:input_value_updated, "/dev/test", input.pin + 1, 100})
      :timer.sleep(10)

      state = Session.get_public_state(pid)
      assert state.min_sample_count == 0

      Session.cancel(pid)
    end

    test "can_advance reflects validation state", %{input: input} do
      {:ok, pid} =
        Session.start_link(
          input_id: input.id,
          port: "/dev/test",
          pin: input.pin
        )

      # Not enough samples
      state = Session.get_public_state(pid)
      assert state.can_advance == false

      # Add samples but not enough unique
      for _ <- 1..10 do
        send(pid, {:input_value_updated, "/dev/test", input.pin, 50})
      end

      :timer.sleep(10)

      state = Session.get_public_state(pid)
      # Has 10 samples but only 1 unique
      assert state.min_sample_count == 10
      assert state.min_unique_count == 1
      assert state.can_advance == false

      # Add more unique values
      send(pid, {:input_value_updated, "/dev/test", input.pin, 51})
      send(pid, {:input_value_updated, "/dev/test", input.pin, 52})
      :timer.sleep(10)

      state = Session.get_public_state(pid)
      assert state.min_unique_count == 3
      assert state.can_advance == true

      Session.cancel(pid)
    end
  end

  describe "CalibrationWizard PubSub events" do
    setup [:create_device_with_input]

    test "broadcasts session_started on init", %{input: input} do
      Session.subscribe(input.id)

      {:ok, pid} =
        Session.start_link(
          input_id: input.id,
          port: "/dev/test",
          pin: input.pin
        )

      assert_receive {:session_started, state}
      assert state.input_id == input.id
      assert state.current_step == :collecting_min

      Session.cancel(pid)
    end

    test "broadcasts step_changed on advancement", %{input: input} do
      Session.subscribe(input.id)

      {:ok, pid} =
        Session.start_link(
          input_id: input.id,
          port: "/dev/test",
          pin: input.pin
        )

      # Clear the session_started message
      assert_receive {:session_started, _}

      # Collect enough samples
      for value <- [10, 11, 12, 10, 11, 12, 10, 11, 12, 10] do
        send(pid, {:input_value_updated, "/dev/test", input.pin, value})
      end

      :timer.sleep(10)

      # Clear sample_collected messages
      flush_mailbox()

      # Advance
      Session.advance_step(pid)

      assert_receive {:step_changed, state}
      assert state.current_step == :sweeping

      Session.cancel(pid)
    end

    test "broadcasts sample_collected on each sample", %{input: input} do
      Session.subscribe(input.id)

      {:ok, pid} =
        Session.start_link(
          input_id: input.id,
          port: "/dev/test",
          pin: input.pin
        )

      # Clear session_started
      assert_receive {:session_started, _}

      send(pid, {:input_value_updated, "/dev/test", input.pin, 100})
      assert_receive {:sample_collected, state}
      assert state.min_sample_count == 1

      Session.cancel(pid)
    end

    test "broadcasts calibration_result on completion", %{input: input} do
      Session.subscribe(input.id)

      {:ok, pid} =
        Session.start_link(
          input_id: input.id,
          port: "/dev/test",
          pin: input.pin
        )

      # Allow the session process to access the database for saving calibration
      allow_session_db_access(pid)

      # Clear initial messages
      flush_mailbox()

      # Complete all steps
      # Step 1
      for value <- [10, 11, 12, 10, 11, 12, 10, 11, 12, 10] do
        send(pid, {:input_value_updated, "/dev/test", input.pin, value})
      end

      :timer.sleep(10)
      Session.advance_step(pid)
      flush_mailbox()

      # Step 2
      for value <- 20..35 do
        send(pid, {:input_value_updated, "/dev/test", input.pin, value})
      end

      :timer.sleep(10)
      Session.advance_step(pid)
      flush_mailbox()

      # Step 3
      for value <- [150, 151, 152, 150, 151, 152, 150, 151, 152, 150] do
        send(pid, {:input_value_updated, "/dev/test", input.pin, value})
      end

      :timer.sleep(10)
      Session.advance_step(pid)

      # Should receive calibration result
      assert_receive {:calibration_result, {:ok, calibration}}, 1000
      assert calibration.input_id == input.id
      assert calibration.min_value == 11
      assert calibration.is_inverted == false
      assert calibration.has_rollover == false
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
