defmodule TswIo.Firmware.Uploader do
  @moduledoc """
  Executes firmware uploads via avrdude.

  Handles building the avrdude command, executing it, parsing
  output for progress updates, and translating errors.
  """

  require Logger

  alias TswIo.Firmware.{Avrdude, BoardConfig}

  @type progress_callback :: (integer(), String.t() -> any())

  @type upload_result ::
          {:ok, %{duration_ms: integer(), output: String.t()}}
          | {:error, atom(), String.t()}

  @doc """
  Upload firmware to a device.

  ## Parameters

    * `port` - Serial port (e.g., "/dev/cu.usbmodem14201")
    * `board_type` - Board type atom (e.g., :uno, :leonardo)
    * `hex_file_path` - Path to the .hex firmware file
    * `progress_callback` - Optional function called with (percent, message)

  ## Returns

    * `{:ok, %{duration_ms: integer, output: String.t()}}` on success
    * `{:error, reason_atom, avrdude_output}` on failure
  """
  @spec upload(String.t(), BoardConfig.board_type(), String.t(), progress_callback() | nil) ::
          upload_result()
  def upload(port, board_type, hex_file_path, progress_callback \\ nil) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, avrdude_path} <- Avrdude.executable_path(),
         {:ok, config} <- BoardConfig.get_config(board_type),
         :ok <- verify_hex_file(hex_file_path) do
      args = build_args(config, port, hex_file_path)

      Logger.info("Running avrdude: #{avrdude_path} #{Enum.join(args, " ")}")

      case run_avrdude(avrdude_path, args, progress_callback) do
        {:ok, output} ->
          duration_ms = System.monotonic_time(:millisecond) - start_time
          {:ok, %{duration_ms: duration_ms, output: output}}

        {:error, output} ->
          {:error, parse_error(output), output}
      end
    end
  end

  # Build avrdude command arguments
  defp build_args(config, port, hex_file_path) do
    [
      "-c",
      config.programmer,
      "-p",
      config.mcu,
      "-P",
      port,
      "-b",
      to_string(config.baud_rate),
      "-D",
      "-U",
      "flash:w:#{hex_file_path}:i",
      "-v"
    ]
  end

  # Verify the hex file exists and is readable
  defp verify_hex_file(path) do
    if File.exists?(path) do
      :ok
    else
      {:error, :hex_file_not_found, "Firmware file not found: #{path}"}
    end
  end

  # Run avrdude and collect output
  defp run_avrdude(avrdude_path, args, progress_callback) do
    port =
      Port.open({:spawn_executable, avrdude_path}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args
      ])

    collect_output(port, "", progress_callback)
  end

  defp collect_output(port, acc, progress_callback) do
    receive do
      {^port, {:data, data}} ->
        new_acc = acc <> data

        # Parse and report progress
        if progress_callback do
          parse_progress(data, progress_callback)
        end

        collect_output(port, new_acc, progress_callback)

      {^port, {:exit_status, 0}} ->
        {:ok, acc}

      {^port, {:exit_status, _code}} ->
        {:error, acc}
    after
      # 2 minute timeout
      120_000 ->
        Port.close(port)
        {:error, acc <> "\n[Timeout: avrdude did not respond within 2 minutes]"}
    end
  end

  # Parse avrdude output for progress updates
  defp parse_progress(data, callback) do
    # avrdude progress format: "Writing | ####... | 45% 1.15s"
    # Also: "Reading | ####... | 100% 0.23s"
    lines = String.split(data, "\n")

    Enum.each(lines, fn line ->
      case Regex.run(~r/(Reading|Writing|Verifying)\s+\|.*?\|\s+(\d+)%/, line) do
        [_, operation, percent_str] ->
          percent = String.to_integer(percent_str)
          message = format_operation(operation, percent)
          callback.(percent, message)

        nil ->
          :ok
      end
    end)
  end

  defp format_operation("Reading", _percent), do: "Reading device..."
  defp format_operation("Writing", percent), do: "Writing flash (#{percent}%)"
  defp format_operation("Verifying", percent), do: "Verifying (#{percent}%)"

  # Parse avrdude error output to determine the error type
  defp parse_error(output) do
    cond do
      String.contains?(output, "can't open device") ->
        :port_not_found

      String.contains?(output, "programmer is not responding") ->
        :bootloader_not_responding

      String.contains?(output, "not in sync") ->
        :bootloader_not_responding

      String.contains?(output, "stk500") and String.contains?(output, "not responding") ->
        :bootloader_not_responding

      String.contains?(output, "device signature") ->
        :wrong_board_type

      String.contains?(output, "verification error") ->
        :verification_failed

      String.contains?(output, "Timeout") ->
        :timeout

      String.contains?(output, "permission denied") ->
        :permission_denied

      true ->
        :unknown_error
    end
  end

  @doc """
  Returns a user-friendly error message for an error atom.
  """
  @spec error_message(atom()) :: String.t()
  def error_message(:port_not_found) do
    """
    Device not found. Please check:
    - Device is connected via USB
    - USB cable supports data (not charge-only)
    - Device appears in the connected devices list
    """
  end

  def error_message(:bootloader_not_responding) do
    """
    Bootloader not responding. Please verify:
    - Selected board type matches your physical board
    - Device is powered on
    - Try a different USB port or cable

    If problem persists, the bootloader may be corrupted.
    """
  end

  def error_message(:wrong_board_type) do
    """
    Board type mismatch. The selected board type doesn't match
    the connected device. Please select the correct board type
    and try again.
    """
  end

  def error_message(:verification_failed) do
    """
    Upload verification failed. The firmware was written but
    could not be verified. This may be caused by:
    - Unstable USB connection
    - Power supply issues
    - Hardware defect

    Please try again with a different USB port or cable.
    """
  end

  def error_message(:timeout) do
    """
    Upload timed out. The device stopped responding during
    the upload process. Please:
    - Check the USB connection
    - Verify the board type is correct
    - Try a different USB port
    """
  end

  def error_message(:permission_denied) do
    """
    Permission denied accessing the serial port. You may need to:
    - Add your user to the dialout group (Linux)
    - Grant terminal access to serial ports (macOS)
    - Run as administrator (Windows)
    """
  end

  def error_message(:hex_file_not_found) do
    "Firmware file not found. Please download the firmware first."
  end

  def error_message(:avrdude_not_found) do
    """
    avrdude not found. Please ensure avrdude is installed:
    - macOS: brew install avrdude
    - Linux: apt-get install avrdude
    - Windows: Download from https://github.com/avrdudes/avrdude/releases
    """
  end

  def error_message(:unknown_error) do
    "An unknown error occurred during upload. Please check the log for details."
  end

  def error_message(_) do
    "An unexpected error occurred."
  end
end
