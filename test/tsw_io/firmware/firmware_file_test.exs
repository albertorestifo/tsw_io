defmodule TswIo.Firmware.FirmwareFileTest do
  use TswIo.DataCase, async: false

  alias TswIo.Firmware.FirmwareFile
  alias TswIo.Firmware.FirmwareRelease

  defp create_release do
    {:ok, release} =
      %FirmwareRelease{}
      |> FirmwareRelease.changeset(%{version: "1.0.0", tag_name: "v1.0.0"})
      |> Repo.insert()

    release
  end

  describe "changeset/2" do
    test "creates valid changeset with required fields" do
      release = create_release()

      attrs = %{
        firmware_release_id: release.id,
        board_type: :uno,
        download_url:
          "https://github.com/albertorestifo/tsw_board/releases/download/v1.0.0/tws-io-arduino-uno.hex"
      }

      changeset = FirmwareFile.changeset(%FirmwareFile{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :board_type) == :uno
    end

    test "creates valid changeset with all fields" do
      release = create_release()

      attrs = %{
        firmware_release_id: release.id,
        board_type: :leonardo,
        download_url: "https://github.com/releases/download/v1.0.0/tws-io-arduino-leonardo.hex",
        file_path: "/cache/tws-io-arduino-leonardo.hex",
        file_size: 22890,
        checksum_sha256: "454b80bcf9612335dc07cff088ea909c232c3c960a15ff640e62eafdc8afcf47",
        downloaded_at: ~U[2025-12-09 12:31:47Z]
      }

      changeset = FirmwareFile.changeset(%FirmwareFile{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :file_size) == 22890
      assert get_change(changeset, :checksum_sha256) =~ "454b80"
    end

    test "requires firmware_release_id" do
      attrs = %{board_type: :uno, download_url: "https://example.com/uno.hex"}

      changeset = FirmwareFile.changeset(%FirmwareFile{}, attrs)

      refute changeset.valid?
      assert %{firmware_release_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires board_type" do
      release = create_release()
      attrs = %{firmware_release_id: release.id, download_url: "https://example.com/uno.hex"}

      changeset = FirmwareFile.changeset(%FirmwareFile{}, attrs)

      refute changeset.valid?
      assert %{board_type: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires download_url" do
      release = create_release()
      attrs = %{firmware_release_id: release.id, board_type: :uno}

      changeset = FirmwareFile.changeset(%FirmwareFile{}, attrs)

      refute changeset.valid?
      assert %{download_url: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates board_type enum" do
      release = create_release()

      attrs = %{
        firmware_release_id: release.id,
        board_type: :invalid_board,
        download_url: "https://example.com/uno.hex"
      }

      changeset = FirmwareFile.changeset(%FirmwareFile{}, attrs)

      refute changeset.valid?
      assert %{board_type: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts all valid board types" do
      release = create_release()

      board_types = [
        :uno,
        :nano,
        :nano_old_bootloader,
        :leonardo,
        :micro,
        :mega2560,
        :sparkfun_pro_micro
      ]

      for board_type <- board_types do
        attrs = %{
          firmware_release_id: release.id,
          board_type: board_type,
          download_url: "https://example.com/#{board_type}.hex"
        }

        changeset = FirmwareFile.changeset(%FirmwareFile{}, attrs)

        assert changeset.valid?, "Expected #{board_type} to be valid"
      end
    end

    test "enforces unique constraint on release_id + board_type" do
      release = create_release()

      attrs = %{
        firmware_release_id: release.id,
        board_type: :uno,
        download_url: "https://example.com/uno.hex"
      }

      {:ok, _file} =
        %FirmwareFile{}
        |> FirmwareFile.changeset(attrs)
        |> Repo.insert()

      {:error, changeset} =
        %FirmwareFile{}
        |> FirmwareFile.changeset(attrs)
        |> Repo.insert()

      assert %{firmware_release_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "enforces foreign key constraint on firmware_release_id" do
      attrs = %{
        firmware_release_id: 999_999,
        board_type: :uno,
        download_url: "https://example.com/uno.hex"
      }

      # SQLite raises a constraint error on insert
      assert_raise Ecto.ConstraintError, fn ->
        %FirmwareFile{}
        |> FirmwareFile.changeset(attrs)
        |> Repo.insert!()
      end
    end
  end

  describe "downloaded?/1" do
    test "returns false when file_path is nil" do
      file = %FirmwareFile{file_path: nil, downloaded_at: ~U[2025-12-09 12:00:00Z]}

      refute FirmwareFile.downloaded?(file)
    end

    test "returns false when downloaded_at is nil" do
      file = %FirmwareFile{file_path: "/cache/uno.hex", downloaded_at: nil}

      refute FirmwareFile.downloaded?(file)
    end

    test "returns true when both file_path and downloaded_at are set" do
      file = %FirmwareFile{file_path: "/cache/uno.hex", downloaded_at: ~U[2025-12-09 12:00:00Z]}

      assert FirmwareFile.downloaded?(file)
    end
  end

  describe "schema associations" do
    test "belongs_to firmware_release" do
      release = create_release()

      {:ok, file} =
        %FirmwareFile{}
        |> FirmwareFile.changeset(%{
          firmware_release_id: release.id,
          board_type: :nano,
          download_url: "https://example.com/nano.hex"
        })
        |> Repo.insert()

      file = Repo.preload(file, :firmware_release)

      assert file.firmware_release.id == release.id
      assert file.firmware_release.tag_name == "v1.0.0"
    end
  end
end
