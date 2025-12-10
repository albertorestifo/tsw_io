defmodule TswIo.Firmware.DownloaderTest do
  use TswIo.DataCase, async: false
  use Mimic

  alias TswIo.Firmware
  alias TswIo.Firmware.Downloader

  setup :verify_on_exit!

  # Real GitHub API response fixture (from curl https://api.github.com/repos/albertorestifo/tsw_board/releases)
  @github_releases_response [
    %{
      "tag_name" => "v1.0.0",
      "name" => "v1.0.0",
      "html_url" => "https://github.com/albertorestifo/tsw_board/releases/tag/v1.0.0",
      "body" => "Initial release with support for Arduino boards",
      "published_at" => "2025-12-09T12:31:04Z",
      "assets" => [
        %{
          "name" => "tws-io-arduino-leonardo.hex",
          "size" => 22890,
          "browser_download_url" =>
            "https://github.com/albertorestifo/tsw_board/releases/download/v1.0.0/tws-io-arduino-leonardo.hex"
        },
        %{
          "name" => "tws-io-arduino-mega-2560.hex",
          "size" => 18582,
          "browser_download_url" =>
            "https://github.com/albertorestifo/tsw_board/releases/download/v1.0.0/tws-io-arduino-mega-2560.hex"
        },
        %{
          "name" => "tws-io-arduino-micro.hex",
          "size" => 22890,
          "browser_download_url" =>
            "https://github.com/albertorestifo/tsw_board/releases/download/v1.0.0/tws-io-arduino-micro.hex"
        },
        %{
          "name" => "tws-io-arduino-nano-old-bootloader.hex",
          "size" => 17113,
          "browser_download_url" =>
            "https://github.com/albertorestifo/tsw_board/releases/download/v1.0.0/tws-io-arduino-nano-old-bootloader.hex"
        },
        %{
          "name" => "tws-io-arduino-nano.hex",
          "size" => 17113,
          "browser_download_url" =>
            "https://github.com/albertorestifo/tsw_board/releases/download/v1.0.0/tws-io-arduino-nano.hex"
        },
        %{
          "name" => "tws-io-arduino-uno.hex",
          "size" => 17113,
          "browser_download_url" =>
            "https://github.com/albertorestifo/tsw_board/releases/download/v1.0.0/tws-io-arduino-uno.hex"
        },
        %{
          "name" => "tws-io-sparkfun-pro-micro.hex",
          "size" => 22890,
          "browser_download_url" =>
            "https://github.com/albertorestifo/tsw_board/releases/download/v1.0.0/tws-io-sparkfun-pro-micro.hex"
        }
      ]
    }
  ]

  describe "check_for_updates/0" do
    test "fetches releases from GitHub and stores them in database" do
      expect(Req, :get, fn url, _opts ->
        assert url =~ "api.github.com/repos/albertorestifo/tsw_board/releases"
        {:ok, %Req.Response{status: 200, body: @github_releases_response}}
      end)

      assert {:ok, releases} = Downloader.check_for_updates()

      # Should have created one release
      assert length(releases) == 1
      assert hd(releases).tag_name == "v1.0.0"
      assert hd(releases).version == "1.0.0"

      # Verify it's in the database
      assert {:ok, release} = Firmware.get_release_by_tag("v1.0.0", preload: [:firmware_files])

      assert release.release_url ==
               "https://github.com/albertorestifo/tsw_board/releases/tag/v1.0.0"

      assert release.release_notes == "Initial release with support for Arduino boards"

      # Should have created firmware files for all 7 board types
      assert length(release.firmware_files) == 7

      # Verify specific board types
      board_types = Enum.map(release.firmware_files, & &1.board_type) |> Enum.sort()

      assert :leonardo in board_types
      assert :mega2560 in board_types
      assert :micro in board_types
      assert :nano in board_types
      assert :nano_old_bootloader in board_types
      assert :uno in board_types
      assert :sparkfun_pro_micro in board_types
    end

    test "handles multiple releases" do
      releases_response = [
        %{
          "tag_name" => "v1.1.0",
          "name" => "v1.1.0",
          "html_url" => "https://github.com/releases/v1.1.0",
          "body" => "Bug fixes",
          "published_at" => "2025-12-10T10:00:00Z",
          "assets" => [
            %{
              "name" => "tws-io-arduino-uno.hex",
              "size" => 17200,
              "browser_download_url" => "https://github.com/releases/v1.1.0/uno.hex"
            }
          ]
        }
        | @github_releases_response
      ]

      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: releases_response}}
      end)

      assert {:ok, releases} = Downloader.check_for_updates()

      assert length(releases) == 2
      versions = Enum.map(releases, & &1.version) |> Enum.sort()
      assert versions == ["1.0.0", "1.1.0"]
    end

    test "updates existing release on re-fetch" do
      # First fetch
      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: @github_releases_response}}
      end)

      assert {:ok, [release1]} = Downloader.check_for_updates()

      # Second fetch with updated notes
      updated_response = [
        %{
          "tag_name" => "v1.0.0",
          "name" => "v1.0.0",
          "html_url" => "https://github.com/releases/v1.0.0",
          "body" => "Updated release notes",
          "published_at" => "2025-12-09T12:31:04Z",
          "assets" => []
        }
      ]

      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: updated_response}}
      end)

      assert {:ok, [release2]} = Downloader.check_for_updates()

      # Should be the same release (same ID)
      assert release1.id == release2.id
      assert release2.release_notes == "Updated release notes"
    end

    test "filters out non-hex assets" do
      release_with_mixed_assets = [
        %{
          "tag_name" => "v1.0.0",
          "name" => "v1.0.0",
          "html_url" => "https://github.com/releases/v1.0.0",
          "body" => nil,
          "published_at" => "2025-12-09T12:31:04Z",
          "assets" => [
            %{
              "name" => "tws-io-arduino-uno.hex",
              "size" => 17113,
              "browser_download_url" => "https://github.com/releases/uno.hex"
            },
            %{
              "name" => "README.md",
              "size" => 1024,
              "browser_download_url" => "https://github.com/releases/README.md"
            },
            %{
              "name" => "firmware.bin",
              "size" => 50000,
              "browser_download_url" => "https://github.com/releases/firmware.bin"
            }
          ]
        }
      ]

      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: release_with_mixed_assets}}
      end)

      assert {:ok, _releases} = Downloader.check_for_updates()

      {:ok, release} = Firmware.get_release_by_tag("v1.0.0", preload: [:firmware_files])

      # Should only have the uno.hex file
      assert length(release.firmware_files) == 1
      assert hd(release.firmware_files).board_type == :uno
    end

    test "handles unknown board types in assets" do
      release_with_unknown_board = [
        %{
          "tag_name" => "v1.0.0",
          "name" => "v1.0.0",
          "html_url" => "https://github.com/releases/v1.0.0",
          "body" => nil,
          "published_at" => "2025-12-09T12:31:04Z",
          "assets" => [
            %{
              "name" => "tws-io-arduino-uno.hex",
              "size" => 17113,
              "browser_download_url" => "https://github.com/releases/uno.hex"
            },
            %{
              "name" => "tws-io-unknown-board.hex",
              "size" => 10000,
              "browser_download_url" => "https://github.com/releases/unknown.hex"
            }
          ]
        }
      ]

      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: release_with_unknown_board}}
      end)

      assert {:ok, _releases} = Downloader.check_for_updates()

      {:ok, release} = Firmware.get_release_by_tag("v1.0.0", preload: [:firmware_files])

      # Should only have uno, unknown board should be filtered
      assert length(release.firmware_files) == 1
      assert hd(release.firmware_files).board_type == :uno
    end

    test "returns error on GitHub API failure" do
      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 403, body: %{"message" => "Rate limit exceeded"}}}
      end)

      assert {:error, {:github_api_error, 403}} = Downloader.check_for_updates()
    end

    test "returns error on network failure" do
      expect(Req, :get, fn _url, _opts ->
        {:error, %Mint.TransportError{reason: :econnrefused}}
      end)

      assert {:error, %Mint.TransportError{reason: :econnrefused}} =
               Downloader.check_for_updates()
    end

    test "handles release without published_at" do
      release_without_date = [
        %{
          "tag_name" => "v1.0.0",
          "name" => "v1.0.0",
          "html_url" => "https://github.com/releases/v1.0.0",
          "body" => nil,
          "published_at" => nil,
          "assets" => []
        }
      ]

      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: release_without_date}}
      end)

      assert {:ok, [release]} = Downloader.check_for_updates()
      assert release.published_at == nil
    end
  end

  describe "download_firmware/1" do
    setup do
      # Create a release with a firmware file
      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: @github_releases_response}}
      end)

      {:ok, [release]} = Downloader.check_for_updates()
      {:ok, release} = Firmware.get_release(release.id, preload: [:firmware_files])

      uno_file = Enum.find(release.firmware_files, &(&1.board_type == :uno))

      # Clean up any existing test files
      cache_dir = Application.app_dir(:tsw_io, "priv/firmware_cache")
      File.mkdir_p!(cache_dir)

      on_exit(fn ->
        # Clean up test files
        cache_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".hex"))
        |> Enum.each(&File.rm(Path.join(cache_dir, &1)))
      end)

      %{release: release, uno_file: uno_file}
    end

    test "downloads firmware file to cache", %{uno_file: uno_file} do
      hex_content = ":10000000DEADBEEF12345678AABBCCDD00112233EE\n:00000001FF\n"

      expect(Req, :get, fn url, opts ->
        assert url =~ "tws-io-arduino-uno.hex"
        assert Keyword.has_key?(opts, :into)
        # Simulate writing to the file stream
        file_stream = Keyword.get(opts, :into)

        Enum.into([hex_content], file_stream)
        {:ok, %Req.Response{status: 200}}
      end)

      assert {:ok, updated_file} = Downloader.download_firmware(uno_file.id)

      assert updated_file.file_path
      assert updated_file.downloaded_at
      assert Firmware.firmware_downloaded?(updated_file)
    end

    test "returns error for non-existent firmware file" do
      assert {:error, :not_found} = Downloader.download_firmware(999_999)
    end

    test "returns error on download failure", %{uno_file: uno_file} do
      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 404}}
      end)

      assert {:error, {:download_failed, 404}} = Downloader.download_firmware(uno_file.id)
    end

    test "returns error on network failure", %{uno_file: uno_file} do
      expect(Req, :get, fn _url, _opts ->
        {:error, %Mint.TransportError{reason: :timeout}}
      end)

      assert {:error, %Mint.TransportError{reason: :timeout}} =
               Downloader.download_firmware(uno_file.id)
    end
  end
end
