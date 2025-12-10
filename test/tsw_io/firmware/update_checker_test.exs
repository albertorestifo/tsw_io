defmodule TswIo.Firmware.UpdateCheckerTest do
  use TswIo.DataCase, async: false

  alias TswIo.Firmware
  alias TswIo.Firmware.UpdateCheck
  alias TswIo.Firmware.UpdateChecker
  alias TswIo.Repo

  import Ecto.Query

  describe "UpdateCheck schema" do
    test "changeset with valid attributes" do
      attrs = %{
        checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
        found_updates: true,
        latest_version: "1.0.0",
        error_message: nil
      }

      changeset = UpdateCheck.changeset(%UpdateCheck{}, attrs)

      assert changeset.valid?
    end

    test "changeset requires checked_at" do
      changeset = UpdateCheck.changeset(%UpdateCheck{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).checked_at
    end

    test "changeset with error_message" do
      attrs = %{
        checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
        found_updates: false,
        error_message: "Network error"
      }

      changeset = UpdateCheck.changeset(%UpdateCheck{}, attrs)

      assert changeset.valid?
    end

    test "changeset defaults found_updates to false" do
      attrs = %{
        checked_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      changeset = UpdateCheck.changeset(%UpdateCheck{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :found_updates) == false
    end

    test "changeset accepts all valid fields" do
      attrs = %{
        checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
        found_updates: true,
        latest_version: "2.0.0",
        error_message: "Some error"
      }

      changeset = UpdateCheck.changeset(%UpdateCheck{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :found_updates) == true
      assert Ecto.Changeset.get_field(changeset, :latest_version) == "2.0.0"
      assert Ecto.Changeset.get_field(changeset, :error_message) == "Some error"
    end
  end

  describe "UpdateCheck persistence" do
    test "insert and retrieve update check" do
      attrs = %{
        checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
        found_updates: true,
        latest_version: "1.2.0"
      }

      {:ok, check} =
        %UpdateCheck{}
        |> UpdateCheck.changeset(attrs)
        |> Repo.insert()

      assert check.id
      assert check.found_updates == true
      assert check.latest_version == "1.2.0"
    end

    test "query checks ordered by checked_at" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      earlier = DateTime.add(now, -3600, :second)

      # Insert in reverse order to test ordering
      {:ok, _} =
        %UpdateCheck{}
        |> UpdateCheck.changeset(%{checked_at: now, found_updates: false})
        |> Repo.insert()

      {:ok, _} =
        %UpdateCheck{}
        |> UpdateCheck.changeset(%{checked_at: earlier, found_updates: true})
        |> Repo.insert()

      checks =
        UpdateCheck
        |> order_by([c], desc: c.checked_at)
        |> Repo.all()

      assert length(checks) >= 2
      [first, second | _rest] = checks
      assert DateTime.compare(first.checked_at, second.checked_at) in [:gt, :eq]
    end

    test "can store and retrieve error messages" do
      attrs = %{
        checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
        found_updates: false,
        error_message: "GitHub API error: 403"
      }

      {:ok, check} =
        %UpdateCheck{}
        |> UpdateCheck.changeset(attrs)
        |> Repo.insert()

      retrieved = Repo.get!(UpdateCheck, check.id)
      assert retrieved.error_message == "GitHub API error: 403"
      assert retrieved.found_updates == false
    end

    test "timestamps are set automatically" do
      attrs = %{
        checked_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      {:ok, check} =
        %UpdateCheck{}
        |> UpdateCheck.changeset(attrs)
        |> Repo.insert()

      assert check.inserted_at
      assert check.updated_at
    end

    test "can query by found_updates" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, check_with_updates} =
        %UpdateCheck{}
        |> UpdateCheck.changeset(%{checked_at: now, found_updates: true, latest_version: "1.0.0"})
        |> Repo.insert()

      {:ok, check_without_updates} =
        %UpdateCheck{}
        |> UpdateCheck.changeset(%{checked_at: now, found_updates: false})
        |> Repo.insert()

      # Query for our specific checks by ID to avoid interference from other tests
      updates_found = Repo.get!(UpdateCheck, check_with_updates.id)
      no_updates = Repo.get!(UpdateCheck, check_without_updates.id)

      assert updates_found.found_updates == true
      assert no_updates.found_updates == false
    end

    test "can store latest_version" do
      attrs = %{
        checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
        found_updates: true,
        latest_version: "3.5.2"
      }

      {:ok, check} =
        %UpdateCheck{}
        |> UpdateCheck.changeset(attrs)
        |> Repo.insert()

      retrieved = Repo.get!(UpdateCheck, check.id)
      assert retrieved.latest_version == "3.5.2"
    end
  end

  describe "UpdateChecker GenServer public API" do
    # Note: The UpdateChecker GenServer is started by the application.
    # These tests verify the public API works correctly.

    test "get_update_status returns valid status" do
      status = UpdateChecker.get_update_status()

      case status do
        :no_update -> assert true
        {:update_available, version} -> assert is_binary(version)
      end
    end

    test "subscribe returns :ok" do
      assert :ok = UpdateChecker.subscribe()
    end

    test "check_now returns :ok without crashing" do
      assert :ok = UpdateChecker.check_now()
    end

    test "dismiss_notification returns :ok" do
      assert :ok = UpdateChecker.dismiss_notification()
    end

    test "dismiss_notification broadcasts event to subscribers" do
      UpdateChecker.subscribe()
      UpdateChecker.dismiss_notification()
      assert_receive :firmware_update_dismissed, 1000
    end

    test "dismiss_notification clears update state" do
      UpdateChecker.dismiss_notification()
      # Give a moment for the state to update
      Process.sleep(50)
      assert UpdateChecker.get_update_status() == :no_update
    end
  end

  describe "Firmware context delegates" do
    test "check_update_status delegates to UpdateChecker" do
      status = Firmware.check_update_status()

      case status do
        :no_update -> assert true
        {:update_available, version} -> assert is_binary(version)
      end
    end

    test "subscribe_update_notifications delegates to UpdateChecker" do
      assert :ok = Firmware.subscribe_update_notifications()
    end

    test "trigger_update_check delegates to UpdateChecker" do
      assert :ok = Firmware.trigger_update_check()
    end

    test "dismiss_update_notification delegates to UpdateChecker" do
      Firmware.subscribe_update_notifications()
      assert :ok = Firmware.dismiss_update_notification()
      assert_receive :firmware_update_dismissed, 1000
    end

    test "all delegates work through Firmware module" do
      # Test the full flow through the Firmware context
      Firmware.subscribe_update_notifications()

      # Check status
      status = Firmware.check_update_status()
      assert status == :no_update or match?({:update_available, _}, status)

      # Trigger check (just verify it doesn't crash)
      assert :ok = Firmware.trigger_update_check()

      # Dismiss
      assert :ok = Firmware.dismiss_update_notification()
      assert_receive :firmware_update_dismissed, 1000
    end
  end

  describe "PubSub subscription" do
    test "subscriber receives firmware_update_dismissed event" do
      Firmware.subscribe_update_notifications()
      UpdateChecker.dismiss_notification()
      assert_receive :firmware_update_dismissed, 1000
    end

    test "multiple processes can subscribe" do
      # Subscribe from this process
      UpdateChecker.subscribe()

      # Spawn another process that also subscribes
      parent = self()

      spawn(fn ->
        UpdateChecker.subscribe()
        send(parent, :subscribed)

        receive do
          :firmware_update_dismissed -> send(parent, :other_received)
        after
          1000 -> send(parent, :other_timeout)
        end
      end)

      assert_receive :subscribed, 500

      # Dismiss notification
      UpdateChecker.dismiss_notification()

      # Both should receive the event
      assert_receive :firmware_update_dismissed, 1000
      assert_receive :other_received, 1000
    end

    test "unsubscribed process does not receive events" do
      # Don't subscribe, just flush any existing messages
      flush_messages()

      # Create another process that will trigger dismiss
      spawn(fn ->
        UpdateChecker.dismiss_notification()
      end)

      # Should NOT receive the dismissed event (not subscribed)
      refute_receive :firmware_update_dismissed, 200
    end
  end

  describe "update status management" do
    test "status is :no_update after dismiss" do
      # Dismiss any existing notification
      UpdateChecker.dismiss_notification()
      Process.sleep(50)

      assert UpdateChecker.get_update_status() == :no_update
    end

    test "get_update_status is consistent across multiple calls" do
      status1 = UpdateChecker.get_update_status()
      status2 = UpdateChecker.get_update_status()
      status3 = UpdateChecker.get_update_status()

      # All calls should return the same status
      assert status1 == status2
      assert status2 == status3
    end
  end

  # Helper to flush all messages from mailbox
  defp flush_messages do
    receive do
      _ -> flush_messages()
    after
      0 -> :ok
    end
  end
end
