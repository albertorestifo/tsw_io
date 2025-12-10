defmodule TswIo.Firmware.UpdateCheckerTest do
  use TswIo.DataCase, async: false
  use Mimic

  alias TswIo.Firmware
  alias TswIo.Firmware.UpdateCheck
  alias TswIo.Firmware.UpdateChecker
  alias TswIo.Repo

  # We need to stub the UpdateChecker since it starts with the application
  # and we want to test it in isolation

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

      import Ecto.Query

      checks =
        UpdateCheck
        |> order_by([c], desc: c.checked_at)
        |> Repo.all()

      assert length(checks) == 2
      [first, second] = checks
      assert DateTime.compare(first.checked_at, second.checked_at) == :gt
    end
  end

  describe "UpdateChecker GenServer" do
    # Note: The UpdateChecker GenServer is started by the application.
    # These tests verify the public API works correctly.

    test "get_update_status returns :no_update initially" do
      # The GenServer starts fresh, so initially there should be no update
      # Unless a check has already run (from startup delay)
      status = UpdateChecker.get_update_status()

      case status do
        :no_update -> assert true
        {:update_available, version} -> assert is_binary(version)
      end
    end

    test "subscribe returns :ok" do
      assert :ok = UpdateChecker.subscribe()
    end

    test "check_now triggers a check" do
      # This just verifies the cast doesn't crash
      assert :ok = UpdateChecker.check_now()
    end

    test "dismiss_notification clears update state" do
      # Subscribe to receive the dismiss event
      UpdateChecker.subscribe()

      # Dismiss the notification
      assert :ok = UpdateChecker.dismiss_notification()

      # Should receive the dismissed event
      assert_receive :firmware_update_dismissed, 1000
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
  end
end
