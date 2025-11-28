defmodule TswIo.Hardware.Calibration.CalculatorTest do
  use ExUnit.Case, async: true

  alias TswIo.Hardware.Calibration.Calculator
  alias TswIo.Hardware.Input.Calibration

  describe "normalize/2" do
    test "normalizes normal input at minimum" do
      calibration = %Calibration{
        min_value: 10,
        max_value: 150,
        is_inverted: false,
        has_rollover: false,
        max_hardware_value: 1023
      }

      assert Calculator.normalize(10, calibration) == 0
    end

    test "normalizes normal input at maximum" do
      calibration = %Calibration{
        min_value: 10,
        max_value: 150,
        is_inverted: false,
        has_rollover: false,
        max_hardware_value: 1023
      }

      assert Calculator.normalize(150, calibration) == 140
    end

    test "normalizes normal input in middle" do
      calibration = %Calibration{
        min_value: 10,
        max_value: 150,
        is_inverted: false,
        has_rollover: false,
        max_hardware_value: 1023
      }

      assert Calculator.normalize(80, calibration) == 70
    end

    test "clamps values below minimum" do
      calibration = %Calibration{
        min_value: 10,
        max_value: 150,
        is_inverted: false,
        has_rollover: false,
        max_hardware_value: 1023
      }

      assert Calculator.normalize(5, calibration) == 0
    end

    test "clamps values above maximum" do
      calibration = %Calibration{
        min_value: 10,
        max_value: 150,
        is_inverted: false,
        has_rollover: false,
        max_hardware_value: 1023
      }

      assert Calculator.normalize(200, calibration) == 140
    end

    test "normalizes inverted input" do
      # For an inverted potentiometer:
      # - Physical minimum position reads raw HIGH value (e.g., 900)
      # - Physical maximum position reads raw LOW value (e.g., 100)
      #
      # Analyzer stores INVERTED values:
      # - min_value = 1023 - 900 = 123 (inverted value at physical min)
      # - max_value = 1023 - 100 = 923 (inverted value at physical max)
      # - is_inverted = true
      #
      # Calculator inverts incoming raw values the same way:
      # - raw 900 -> 1023 - 900 = 123 -> clamped 123 -> normalized 0 ✓
      # - raw 100 -> 1023 - 100 = 923 -> clamped 923 -> normalized 800 ✓

      calibration = %Calibration{
        min_value: 123,
        max_value: 923,
        is_inverted: true,
        has_rollover: false,
        max_hardware_value: 1023
      }

      # At physical min (raw 900): should normalize to 0
      assert Calculator.normalize(900, calibration) == 0

      # At physical max (raw 100): should normalize to total_travel (800)
      assert Calculator.normalize(100, calibration) == 800

      # In the middle (raw 500): 1023 - 500 = 523, normalized = 523 - 123 = 400
      assert Calculator.normalize(500, calibration) == 400
    end

    test "normalizes with rollover" do
      calibration = %Calibration{
        min_value: 1010,
        max_value: 1030,
        is_inverted: false,
        has_rollover: true,
        max_hardware_value: 1023
      }

      # At min (raw 1010), normalized = 0
      assert Calculator.normalize(1010, calibration) == 0

      # After rollover, raw 5 should map correctly
      # 5 < 1010, so we add 1024: 5 + 1024 = 1029
      # 1029 is within 1010..1030, so normalized = 1029 - 1010 = 19
      assert Calculator.normalize(5, calibration) == 19

      # At max (raw 1030, which would be 6 after rollover: 6 + 1024 = 1030)
      # But if we read 1023 before rollover: 1023 - 1010 = 13
      assert Calculator.normalize(1023, calibration) == 13
    end
  end

  describe "total_travel/1" do
    test "returns difference between max and min" do
      calibration = %Calibration{
        min_value: 10,
        max_value: 150,
        is_inverted: false,
        has_rollover: false,
        max_hardware_value: 1023
      }

      assert Calculator.total_travel(calibration) == 140
    end

    test "works with rollover values" do
      calibration = %Calibration{
        min_value: 1010,
        max_value: 1030,
        is_inverted: false,
        has_rollover: true,
        max_hardware_value: 1023
      }

      assert Calculator.total_travel(calibration) == 20
    end
  end
end
