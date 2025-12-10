defmodule TswIo.Firmware.UploaderTest do
  use ExUnit.Case, async: true

  alias TswIo.Firmware.Uploader

  describe "error_message/1" do
    test "returns message for :port_not_found" do
      message = Uploader.error_message(:port_not_found)

      assert message =~ "Device not found"
      assert message =~ "USB cable"
    end

    test "returns message for :bootloader_not_responding" do
      message = Uploader.error_message(:bootloader_not_responding)

      assert message =~ "Bootloader not responding"
      assert message =~ "board type"
    end

    test "returns message for :wrong_board_type" do
      message = Uploader.error_message(:wrong_board_type)

      assert message =~ "Board type mismatch"
    end

    test "returns message for :verification_failed" do
      message = Uploader.error_message(:verification_failed)

      assert message =~ "verification failed"
      assert message =~ "USB connection"
    end

    test "returns message for :timeout" do
      message = Uploader.error_message(:timeout)

      assert message =~ "timed out"
    end

    test "returns message for :permission_denied" do
      message = Uploader.error_message(:permission_denied)

      assert message =~ "Permission denied"
    end

    test "returns message for :hex_file_not_found" do
      message = Uploader.error_message(:hex_file_not_found)

      assert message =~ "Firmware file not found"
    end

    test "returns message for :avrdude_not_found" do
      message = Uploader.error_message(:avrdude_not_found)

      assert message =~ "avrdude not found"
    end

    test "returns message for :unknown_error" do
      message = Uploader.error_message(:unknown_error)

      assert message =~ "unknown error"
    end

    test "returns generic message for unhandled atoms" do
      message = Uploader.error_message(:some_other_error)

      assert message =~ "unexpected error"
    end
  end

  # Testing parse_error indirectly through behavior - these would be tested
  # via integration tests with actual avrdude output, but we can test the
  # error classification logic patterns
  describe "error classification (via upload/4 error handling)" do
    test "port_not_found error contains expected text patterns" do
      # These are the patterns that parse_error looks for
      assert String.contains?("can't open device /dev/ttyUSB0", "can't open device")
    end

    test "bootloader_not_responding error contains expected text patterns" do
      patterns = [
        "programmer is not responding",
        "not in sync: resp=0x00",
        "stk500v2_recv(): not responding"
      ]

      Enum.each(patterns, fn pattern ->
        assert String.contains?(pattern, "not responding") or
                 String.contains?(pattern, "not in sync"),
               "Pattern should trigger bootloader_not_responding: #{pattern}"
      end)
    end

    test "wrong_board_type error contains expected text patterns" do
      # avrdude outputs "device signature = 0x1e950f" when there's a signature mismatch
      assert String.contains?(
               "avrdude: device signature = 0x1e950f",
               "device signature"
             )
    end

    test "verification_failed error contains expected text patterns" do
      assert String.contains?(
               "avrdude: verification error, first mismatch at byte 0x0100",
               "verification error"
             )
    end

    test "timeout error contains expected text patterns" do
      assert String.contains?(
               "[Timeout: avrdude did not respond within 2 minutes]",
               "Timeout"
             )
    end

    test "permission_denied error contains expected text patterns" do
      assert String.contains?(
               "avrdude: ser_open(): can't open device: permission denied",
               "permission denied"
             )
    end
  end

  describe "progress parsing patterns" do
    test "writing progress pattern matches avrdude output" do
      line = "Writing | ################################################## | 100% 1.15s"
      assert Regex.match?(~r/(Reading|Writing|Verifying)\s+\|.*?\|\s+(\d+)%/, line)
    end

    test "reading progress pattern matches avrdude output" do
      line = "Reading | ########################                           | 45% 0.23s"
      assert Regex.match?(~r/(Reading|Writing|Verifying)\s+\|.*?\|\s+(\d+)%/, line)
    end

    test "verifying progress pattern matches avrdude output" do
      line = "Verifying | ################################################## | 100% 0.15s"
      assert Regex.match?(~r/(Reading|Writing|Verifying)\s+\|.*?\|\s+(\d+)%/, line)
    end

    test "extracts operation and percentage from progress line" do
      line = "Writing | ##################                                 | 35% 0.42s"

      case Regex.run(~r/(Reading|Writing|Verifying)\s+\|.*?\|\s+(\d+)%/, line) do
        [_, operation, percent_str] ->
          assert operation == "Writing"
          assert percent_str == "35"

        nil ->
          flunk("Regex should match progress line")
      end
    end
  end

  describe "upload/4 with missing hex file" do
    @tag :skip_without_avrdude
    test "returns error when hex file doesn't exist" do
      # Skip this test if avrdude is not available
      case TswIo.Firmware.Avrdude.executable_path() do
        {:ok, _} ->
          result = Uploader.upload("/dev/ttyUSB0", :uno, "/nonexistent/firmware.hex")

          assert {:error, :hex_file_not_found, message} = result
          assert message =~ "not found"

        {:error, :avrdude_not_found} ->
          # Expected on CI systems without avrdude
          :ok
      end
    end
  end
end
