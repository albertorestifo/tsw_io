defmodule TswIo.FirmwareTest do
  use TswIo.DataCase, async: false

  alias TswIo.Firmware

  # Helper to create a release with files
  defp create_release_with_files(attrs \\ %{}) do
    release_attrs =
      Map.merge(
        %{
          version: "1.0.0",
          tag_name: "v1.0.0",
          release_url: "https://github.com/albertorestifo/tsw_board/releases/tag/v1.0.0",
          published_at: ~U[2025-12-09 12:31:04Z]
        },
        attrs
      )

    {:ok, release} = Firmware.create_release(release_attrs)

    # Create firmware files for common board types
    {:ok, uno_file} =
      Firmware.create_firmware_file(release.id, %{
        board_type: :uno,
        download_url: "https://github.com/releases/download/v1.0.0/tws-io-arduino-uno.hex",
        file_size: 17113
      })

    {:ok, nano_file} =
      Firmware.create_firmware_file(release.id, %{
        board_type: :nano,
        download_url: "https://github.com/releases/download/v1.0.0/tws-io-arduino-nano.hex",
        file_size: 17113
      })

    {:ok, leonardo_file} =
      Firmware.create_firmware_file(release.id, %{
        board_type: :leonardo,
        download_url: "https://github.com/releases/download/v1.0.0/tws-io-arduino-leonardo.hex",
        file_size: 22890
      })

    # Preload the firmware_release association for file path calculation
    uno_file = %{uno_file | firmware_release: release}
    nano_file = %{nano_file | firmware_release: release}
    leonardo_file = %{leonardo_file | firmware_release: release}

    {release, [uno_file, nano_file, leonardo_file]}
  end

  describe "list_releases/1" do
    test "returns empty list when no releases exist" do
      assert [] = Firmware.list_releases()
    end

    test "returns releases ordered by published_at descending" do
      {:ok, old_release} =
        Firmware.create_release(%{
          version: "0.9.0",
          tag_name: "v0.9.0",
          published_at: ~U[2025-11-01 12:00:00Z]
        })

      {:ok, new_release} =
        Firmware.create_release(%{
          version: "1.0.0",
          tag_name: "v1.0.0",
          published_at: ~U[2025-12-09 12:00:00Z]
        })

      releases = Firmware.list_releases()

      assert length(releases) == 2
      assert hd(releases).id == new_release.id
      assert List.last(releases).id == old_release.id
    end

    test "preloads associations when requested" do
      {release, _files} = create_release_with_files()

      releases = Firmware.list_releases(preload: [:firmware_files])

      assert [loaded_release] = releases
      assert loaded_release.id == release.id
      assert length(loaded_release.firmware_files) == 3
    end
  end

  describe "get_latest_release/1" do
    test "returns error when no releases exist" do
      assert {:error, :not_found} = Firmware.get_latest_release()
    end

    test "returns the most recent release by published_at" do
      {:ok, _old_release} =
        Firmware.create_release(%{
          version: "0.9.0",
          tag_name: "v0.9.0",
          published_at: ~U[2025-11-01 12:00:00Z]
        })

      {:ok, new_release} =
        Firmware.create_release(%{
          version: "1.0.0",
          tag_name: "v1.0.0",
          published_at: ~U[2025-12-09 12:00:00Z]
        })

      assert {:ok, release} = Firmware.get_latest_release()
      assert release.id == new_release.id
      assert release.version == "1.0.0"
    end

    test "preloads associations when requested" do
      {_release, _files} = create_release_with_files()

      {:ok, release} = Firmware.get_latest_release(preload: [:firmware_files])

      assert length(release.firmware_files) == 3
    end
  end

  describe "get_release/2" do
    test "returns release by id" do
      {release, _files} = create_release_with_files()

      assert {:ok, found} = Firmware.get_release(release.id)
      assert found.id == release.id
      assert found.tag_name == "v1.0.0"
    end

    test "returns error when release not found" do
      assert {:error, :not_found} = Firmware.get_release(999_999)
    end

    test "preloads associations when requested" do
      {release, _files} = create_release_with_files()

      {:ok, found} = Firmware.get_release(release.id, preload: [:firmware_files])

      assert length(found.firmware_files) == 3
    end
  end

  describe "get_release_by_tag/2" do
    test "returns release by tag_name" do
      {release, _files} = create_release_with_files()

      assert {:ok, found} = Firmware.get_release_by_tag("v1.0.0")
      assert found.id == release.id
    end

    test "returns error when tag not found" do
      assert {:error, :not_found} = Firmware.get_release_by_tag("v99.0.0")
    end
  end

  describe "create_release/1" do
    test "creates release with valid attributes" do
      attrs = %{
        version: "2.0.0",
        tag_name: "v2.0.0",
        release_url: "https://github.com/releases/v2.0.0",
        release_notes: "New features",
        published_at: ~U[2025-12-10 10:00:00Z]
      }

      assert {:ok, release} = Firmware.create_release(attrs)
      assert release.version == "2.0.0"
      assert release.tag_name == "v2.0.0"
    end

    test "returns error with invalid attributes" do
      assert {:error, changeset} = Firmware.create_release(%{})
      assert %{version: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "upsert_release/1" do
    test "creates new release when tag doesn't exist" do
      attrs = %{
        version: "1.0.0",
        tag_name: "v1.0.0",
        release_notes: "Initial release"
      }

      assert {:ok, release} = Firmware.upsert_release(attrs)
      assert release.version == "1.0.0"
      assert release.release_notes == "Initial release"
    end

    test "updates existing release when tag exists" do
      {:ok, original} =
        Firmware.create_release(%{
          version: "1.0.0",
          tag_name: "v1.0.0",
          release_notes: "Original"
        })

      attrs = %{
        version: "1.0.0",
        tag_name: "v1.0.0",
        release_notes: "Updated notes"
      }

      assert {:ok, updated} = Firmware.upsert_release(attrs)
      assert updated.id == original.id
      assert updated.release_notes == "Updated notes"
    end
  end

  describe "get_firmware_file/2" do
    test "returns firmware file by id" do
      {_release, [uno_file | _rest]} = create_release_with_files()

      assert {:ok, found} = Firmware.get_firmware_file(uno_file.id)
      assert found.id == uno_file.id
      assert found.board_type == :uno
    end

    test "returns error when file not found" do
      assert {:error, :not_found} = Firmware.get_firmware_file(999_999)
    end
  end

  describe "get_firmware_file_for_board/2" do
    test "returns firmware file for specific release and board type" do
      {release, _files} = create_release_with_files()

      assert {:ok, file} = Firmware.get_firmware_file_for_board(release.id, :leonardo)
      assert file.board_type == :leonardo
      assert file.firmware_release_id == release.id
    end

    test "returns error when no file for board type" do
      {release, _files} = create_release_with_files()

      assert {:error, :not_found} = Firmware.get_firmware_file_for_board(release.id, :mega2560)
    end
  end

  describe "create_firmware_file/2" do
    test "creates firmware file for release" do
      {:ok, release} = Firmware.create_release(%{version: "1.0.0", tag_name: "v1.0.0"})

      attrs = %{
        board_type: :micro,
        download_url: "https://example.com/micro.hex",
        file_size: 22890
      }

      assert {:ok, file} = Firmware.create_firmware_file(release.id, attrs)
      assert file.firmware_release_id == release.id
      assert file.board_type == :micro
    end
  end

  describe "update_firmware_file/2" do
    test "updates firmware file attributes" do
      {_release, [uno_file | _rest]} = create_release_with_files()

      attrs = %{
        file_size: 12345,
        checksum_sha256: "abc123"
      }

      assert {:ok, updated} = Firmware.update_firmware_file(uno_file, attrs)
      assert updated.file_size == 12345
      assert updated.checksum_sha256 == "abc123"
    end
  end

  describe "firmware_downloaded?/1" do
    test "returns false when file not downloaded" do
      {_release, [uno_file | _rest]} = create_release_with_files()

      refute Firmware.firmware_downloaded?(uno_file)
    end

    test "returns true when file exists on disk" do
      {_release, [uno_file | _rest]} = create_release_with_files()

      # Create the actual file on disk
      path = TswIo.Firmware.FilePath.firmware_path(uno_file)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "test content")

      assert Firmware.firmware_downloaded?(uno_file)

      # Cleanup
      File.rm!(path)
    end
  end

  describe "list_upload_history/1" do
    test "returns empty list when no history exists" do
      assert [] = Firmware.list_upload_history()
    end

    test "returns history ordered by started_at descending" do
      {:ok, old_upload} =
        Firmware.create_upload_history(%{
          upload_id: "old_upload",
          port: "/dev/ttyUSB0",
          board_type: :uno
        })

      # Small delay to ensure different timestamps
      Process.sleep(10)

      {:ok, new_upload} =
        Firmware.create_upload_history(%{
          upload_id: "new_upload",
          port: "/dev/ttyUSB1",
          board_type: :nano
        })

      history = Firmware.list_upload_history()

      assert length(history) == 2
      assert hd(history).upload_id == new_upload.upload_id
      assert List.last(history).upload_id == old_upload.upload_id
    end

    test "respects limit option" do
      for i <- 1..5 do
        {:ok, _} =
          Firmware.create_upload_history(%{
            upload_id: "upload_#{i}",
            port: "/dev/ttyUSB0",
            board_type: :uno
          })
      end

      history = Firmware.list_upload_history(limit: 3)

      assert length(history) == 3
    end
  end

  describe "create_upload_history/1" do
    test "creates upload history with started status" do
      attrs = %{
        upload_id: "upload_123",
        port: "/dev/ttyUSB0",
        board_type: :leonardo
      }

      assert {:ok, history} = Firmware.create_upload_history(attrs)
      assert history.status == :started
      assert history.started_at
    end
  end

  describe "get_upload_history/1" do
    test "returns history by upload_id" do
      {:ok, created} =
        Firmware.create_upload_history(%{
          upload_id: "find_me",
          port: "/dev/ttyUSB0",
          board_type: :uno
        })

      assert {:ok, found} = Firmware.get_upload_history("find_me")
      assert found.id == created.id
    end

    test "returns error when not found" do
      assert {:error, :not_found} = Firmware.get_upload_history("nonexistent")
    end
  end

  describe "complete_upload/2" do
    test "marks upload as completed" do
      {:ok, history} =
        Firmware.create_upload_history(%{
          upload_id: "complete_test",
          port: "/dev/ttyUSB0",
          board_type: :uno
        })

      Process.sleep(10)

      assert {:ok, completed} = Firmware.complete_upload(history, %{avrdude_output: "success"})
      assert completed.status == :completed
      assert completed.completed_at
      assert completed.duration_ms >= 0
    end
  end

  describe "fail_upload/3" do
    test "marks upload as failed with error message" do
      {:ok, history} =
        Firmware.create_upload_history(%{
          upload_id: "fail_test",
          port: "/dev/ttyUSB0",
          board_type: :leonardo
        })

      assert {:ok, failed} =
               Firmware.fail_upload(history, "Device not responding", "avrdude: error")

      assert failed.status == :failed
      assert failed.error_message == "Device not responding"
      assert failed.avrdude_output == "avrdude: error"
    end
  end

  describe "cancel_upload_history/1" do
    test "marks upload as cancelled" do
      {:ok, history} =
        Firmware.create_upload_history(%{
          upload_id: "cancel_test",
          port: "/dev/ttyUSB0",
          board_type: :micro
        })

      assert {:ok, cancelled} = Firmware.cancel_upload_history(history)
      assert cancelled.status == :cancelled
      assert cancelled.completed_at
    end
  end

  describe "compare_versions/2" do
    test "returns :gt when first version is greater" do
      assert :gt = Firmware.compare_versions("2.0.0", "1.0.0")
      assert :gt = Firmware.compare_versions("1.1.0", "1.0.0")
      assert :gt = Firmware.compare_versions("1.0.1", "1.0.0")
    end

    test "returns :lt when first version is less" do
      assert :lt = Firmware.compare_versions("1.0.0", "2.0.0")
      assert :lt = Firmware.compare_versions("1.0.0", "1.1.0")
      assert :lt = Firmware.compare_versions("1.0.0", "1.0.1")
    end

    test "returns :eq when versions are equal" do
      assert :eq = Firmware.compare_versions("1.0.0", "1.0.0")
    end

    test "handles v prefix" do
      assert :gt = Firmware.compare_versions("v2.0.0", "v1.0.0")
      assert :eq = Firmware.compare_versions("v1.0.0", "1.0.0")
      assert :lt = Firmware.compare_versions("1.0.0", "v2.0.0")
    end
  end

  describe "update_available?/1" do
    test "returns false when no releases exist" do
      refute Firmware.update_available?("1.0.0")
    end

    test "returns true when newer version available" do
      {:ok, _release} =
        Firmware.create_release(%{
          version: "2.0.0",
          tag_name: "v2.0.0",
          published_at: DateTime.utc_now()
        })

      assert Firmware.update_available?("1.0.0")
    end

    test "returns false when current version is latest" do
      {:ok, _release} =
        Firmware.create_release(%{
          version: "1.0.0",
          tag_name: "v1.0.0",
          published_at: DateTime.utc_now()
        })

      refute Firmware.update_available?("1.0.0")
      refute Firmware.update_available?("2.0.0")
    end
  end

  describe "delegated functions" do
    test "board_types/0 returns all board types" do
      types = Firmware.board_types()

      assert :uno in types
      assert :nano in types
      assert :leonardo in types
    end

    test "get_board_config/1 returns board configuration" do
      assert {:ok, config} = Firmware.get_board_config(:uno)
      assert config.name == "Arduino Uno"
    end

    test "board_select_options/0 returns select options" do
      options = Firmware.board_select_options()

      assert Enum.all?(options, fn {name, type} -> is_binary(name) and is_atom(type) end)
    end
  end
end
