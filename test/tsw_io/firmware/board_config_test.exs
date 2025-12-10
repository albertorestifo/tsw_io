defmodule TswIo.Firmware.BoardConfigTest do
  use ExUnit.Case, async: true

  alias TswIo.Firmware.BoardConfig

  describe "board_types/0" do
    test "returns all supported board types" do
      types = BoardConfig.board_types()

      assert :uno in types
      assert :nano in types
      assert :nano_old_bootloader in types
      assert :leonardo in types
      assert :micro in types
      assert :mega2560 in types
      assert :sparkfun_pro_micro in types
      assert length(types) == 7
    end
  end

  describe "get_config/1" do
    test "returns config for Arduino Uno" do
      assert {:ok, config} = BoardConfig.get_config(:uno)
      assert config.name == "Arduino Uno"
      assert config.mcu == "m328p"
      assert config.programmer == "arduino"
      assert config.baud_rate == 115_200
      assert config.hex_filename == "tws-io-arduino-uno.hex"
    end

    test "returns config for Arduino Nano" do
      assert {:ok, config} = BoardConfig.get_config(:nano)
      assert config.name == "Arduino Nano"
      assert config.mcu == "m328p"
      assert config.programmer == "arduino"
      assert config.baud_rate == 57_600
      assert config.hex_filename == "tws-io-arduino-nano.hex"
    end

    test "returns config for Arduino Nano (old bootloader)" do
      assert {:ok, config} = BoardConfig.get_config(:nano_old_bootloader)
      assert config.name == "Arduino Nano (Old Bootloader)"
      assert config.mcu == "m328p"
      assert config.programmer == "arduino"
      assert config.baud_rate == 57_600
      assert config.hex_filename == "tws-io-arduino-nano-old-bootloader.hex"
    end

    test "returns config for Arduino Leonardo" do
      assert {:ok, config} = BoardConfig.get_config(:leonardo)
      assert config.name == "Arduino Leonardo"
      assert config.mcu == "m32u4"
      assert config.programmer == "avr109"
      assert config.baud_rate == 57_600
      assert config.hex_filename == "tws-io-arduino-leonardo.hex"
    end

    test "returns config for Arduino Micro" do
      assert {:ok, config} = BoardConfig.get_config(:micro)
      assert config.name == "Arduino Micro"
      assert config.mcu == "m32u4"
      assert config.programmer == "avr109"
      assert config.baud_rate == 57_600
      assert config.hex_filename == "tws-io-arduino-micro.hex"
    end

    test "returns config for Arduino Mega 2560" do
      assert {:ok, config} = BoardConfig.get_config(:mega2560)
      assert config.name == "Arduino Mega 2560"
      assert config.mcu == "m2560"
      assert config.programmer == "wiring"
      assert config.baud_rate == 115_200
      assert config.hex_filename == "tws-io-arduino-mega-2560.hex"
    end

    test "returns config for SparkFun Pro Micro" do
      assert {:ok, config} = BoardConfig.get_config(:sparkfun_pro_micro)
      assert config.name == "SparkFun Pro Micro"
      assert config.mcu == "m32u4"
      assert config.programmer == "avr109"
      assert config.baud_rate == 57_600
      assert config.hex_filename == "tws-io-sparkfun-pro-micro.hex"
    end

    test "returns error for unknown board type" do
      assert {:error, :unknown_board} = BoardConfig.get_config(:unknown_board)
    end
  end

  describe "get_config!/1" do
    test "returns config for known board type" do
      config = BoardConfig.get_config!(:uno)
      assert config.name == "Arduino Uno"
    end

    test "raises for unknown board type" do
      assert_raise ArgumentError, ~r/Unknown board type/, fn ->
        BoardConfig.get_config!(:unknown_board)
      end
    end
  end

  describe "all_configs/0" do
    test "returns all board configurations" do
      configs = BoardConfig.all_configs()

      assert length(configs) == 7

      assert Enum.all?(configs, fn {type, config} ->
               is_atom(type) and is_map(config) and Map.has_key?(config, :name)
             end)
    end

    test "all configs have required fields" do
      required_fields = [:name, :mcu, :programmer, :baud_rate, :hex_filename]

      for {_type, config} <- BoardConfig.all_configs() do
        for field <- required_fields do
          assert Map.has_key?(config, field),
                 "Config for #{config[:name]} missing field #{field}"
        end
      end
    end
  end

  describe "select_options/0" do
    test "returns options suitable for form select" do
      options = BoardConfig.select_options()

      assert length(options) == 7

      assert Enum.all?(options, fn {name, type} ->
               is_binary(name) and is_atom(type)
             end)
    end

    test "options are sorted alphabetically by name" do
      options = BoardConfig.select_options()
      names = Enum.map(options, fn {name, _type} -> name end)

      assert names == Enum.sort(names)
    end

    test "includes all board types" do
      options = BoardConfig.select_options()
      types = Enum.map(options, fn {_name, type} -> type end)

      assert :uno in types
      assert :leonardo in types
      assert :sparkfun_pro_micro in types
    end
  end

  describe "detect_board_type/1" do
    test "detects Arduino Uno from filename" do
      assert {:ok, :uno} = BoardConfig.detect_board_type("tws-io-arduino-uno.hex")
    end

    test "detects Arduino Nano from filename" do
      assert {:ok, :nano} = BoardConfig.detect_board_type("tws-io-arduino-nano.hex")
    end

    test "detects Arduino Nano (old bootloader) from filename" do
      assert {:ok, :nano_old_bootloader} =
               BoardConfig.detect_board_type("tws-io-arduino-nano-old-bootloader.hex")
    end

    test "detects Arduino Leonardo from filename" do
      assert {:ok, :leonardo} = BoardConfig.detect_board_type("tws-io-arduino-leonardo.hex")
    end

    test "detects Arduino Micro from filename" do
      assert {:ok, :micro} = BoardConfig.detect_board_type("tws-io-arduino-micro.hex")
    end

    test "detects Arduino Mega 2560 from filename" do
      assert {:ok, :mega2560} = BoardConfig.detect_board_type("tws-io-arduino-mega-2560.hex")
    end

    test "detects SparkFun Pro Micro from filename" do
      assert {:ok, :sparkfun_pro_micro} =
               BoardConfig.detect_board_type("tws-io-sparkfun-pro-micro.hex")
    end

    test "returns error for unknown filename" do
      assert :error = BoardConfig.detect_board_type("unknown-board.hex")
    end

    test "returns error for non-hex file" do
      assert :error = BoardConfig.detect_board_type("firmware.bin")
    end

    test "returns error for partial match" do
      assert :error = BoardConfig.detect_board_type("arduino-uno.hex")
    end
  end
end
