defmodule TswIo.Hardware.Calibration.AnalyzerTest do
  use ExUnit.Case, async: true

  alias TswIo.Hardware.Calibration.Analyzer

  describe "analyze_sweep/2" do
    test "returns empty list for normal increasing sweep" do
      sweep_samples = [10, 30, 50, 70, 90, 110, 130, 150]

      assert {:ok, []} = Analyzer.analyze_sweep(sweep_samples, 1023)
    end

    test "detects inverted input from decreasing sweep" do
      sweep_samples = [150, 130, 110, 90, 70, 50, 30, 10]

      assert {:ok, [:inverted]} = Analyzer.analyze_sweep(sweep_samples, 1023)
    end

    test "detects rollover from large delta" do
      sweep_samples = [1010, 1015, 1020, 1023, 0, 5, 10, 15]

      assert {:ok, [:rollover]} = Analyzer.analyze_sweep(sweep_samples, 1023)
    end

    test "detects both inverted and rollover" do
      # Decreasing values that wrap around
      sweep_samples = [15, 10, 5, 0, 1023, 1020, 1015, 1010]

      assert {:ok, characteristics} = Analyzer.analyze_sweep(sweep_samples, 1023)
      assert :inverted in characteristics
      assert :rollover in characteristics
    end

    test "returns empty list for insufficient samples" do
      assert {:ok, []} = Analyzer.analyze_sweep([100], 1023)
      assert {:ok, []} = Analyzer.analyze_sweep([], 1023)
    end

    test "handles noisy but increasing data" do
      # Mostly increasing with some noise
      sweep_samples = [10, 15, 12, 20, 25, 22, 30, 35, 40, 50]

      assert {:ok, []} = Analyzer.analyze_sweep(sweep_samples, 1023)
    end

    test "handles noisy but decreasing data" do
      # Mostly decreasing with some noise
      sweep_samples = [50, 45, 48, 40, 35, 38, 30, 25, 20, 10]

      assert {:ok, [:inverted]} = Analyzer.analyze_sweep(sweep_samples, 1023)
    end
  end

  describe "calculate_min/3" do
    test "returns median for normal input" do
      min_samples = [10, 12, 11, 9, 10, 11, 10, 12, 9, 10]

      result = Analyzer.calculate_min(min_samples, [], 1023)

      assert result == 10
    end

    test "returns inverted median for inverted input" do
      # For inverted, the raw median at min position is 900 (high value)
      # The stored value should be 1023 - 900 = 123
      min_samples = [898, 900, 902, 899, 901, 900, 899, 901, 900, 902]

      result = Analyzer.calculate_min(min_samples, [:inverted], 1023)

      assert result == 1023 - 900
      assert result == 123
    end
  end

  describe "calculate_max/4" do
    test "returns median for normal input" do
      min_samples = [10, 12, 11, 9, 10]
      max_samples = [150, 152, 148, 151, 149]

      result = Analyzer.calculate_max(max_samples, min_samples, [], 1023)

      assert result == 150
    end

    test "returns inverted median for inverted input" do
      # For inverted: min position has high raw (900), max position has low raw (100)
      min_samples = [898, 900, 902, 899, 901]
      max_samples = [98, 100, 102, 99, 101]

      result = Analyzer.calculate_max(max_samples, min_samples, [:inverted], 1023)

      # min_median = 900, max_median = 100
      # effective_min = 1023 - 900 = 123
      # effective_max = 1023 - 100 = 923
      assert result == 923
    end

    test "accounts for rollover in normal direction" do
      min_samples = [1010, 1012, 1011, 1009, 1010]
      max_samples = [15, 17, 16, 14, 15]

      result = Analyzer.calculate_max(max_samples, min_samples, [:rollover], 1023)

      # effective_min = 1010, effective_max = 15
      # With rollover: 15 + (1023 - 1010 + 1) = 15 + 14 = 29
      assert result == 29
    end

    test "accounts for rollover in inverted direction" do
      # Inverted with rollover: values decrease and wrap
      min_samples = [15, 17, 16, 14, 15]
      max_samples = [1010, 1012, 1011, 1009, 1010]

      result =
        Analyzer.calculate_max(max_samples, min_samples, [:inverted, :rollover], 1023)

      # min_median = 15, max_median = 1010
      # effective_min = 1023 - 15 = 1008
      # effective_max = 1023 - 1010 = 13
      # With rollover: 13 + (1023 - 1008 + 1) = 13 + 16 = 29
      assert result == 29
    end
  end
end
