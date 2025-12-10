defmodule TswIo.Serial.ProtocolTest do
  use ExUnit.Case, async: true

  alias TswIo.Serial.Protocol.{
    IdentityRequest,
    IdentityResponse,
    Configure,
    ConfigurationStored,
    ConfigurationError,
    InputValue,
    Heartbeat
  }

  describe "IdentityRequest" do
    test "type returns 0x00" do
      assert IdentityRequest.type() == 0x00
    end

    test "encode encodes request_id correctly" do
      request = %IdentityRequest{request_id: 0x12345678}
      {:ok, encoded} = IdentityRequest.encode(request)

      # Type (0x00) + request_id (0x12345678 little endian)
      assert encoded == <<0x00, 0x78, 0x56, 0x34, 0x12>>
    end

    test "decode decodes valid message" do
      # Type (0x00) + request_id (0x12345678 little endian)
      binary = <<0x00, 0x78, 0x56, 0x34, 0x12>>
      {:ok, decoded} = IdentityRequest.decode(binary)

      assert decoded == %IdentityRequest{request_id: 0x12345678}
    end

    test "decode returns error for invalid message type" do
      assert IdentityRequest.decode(<<0x01, 0x78, 0x56, 0x34, 0x12>>) ==
               {:error, :invalid_message}
    end

    test "decode returns error for incomplete message" do
      assert IdentityRequest.decode(<<0x00, 0x78, 0x56>>) == {:error, :invalid_message}
    end

    test "roundtrip encode/decode" do
      original = %IdentityRequest{request_id: 0xDEADBEEF}
      {:ok, encoded} = IdentityRequest.encode(original)
      {:ok, decoded} = IdentityRequest.decode(encoded)

      assert decoded == original
    end
  end

  describe "IdentityResponse" do
    test "type returns 0x01" do
      assert IdentityResponse.type() == 0x01
    end

    test "encode encodes all fields correctly" do
      response = %IdentityResponse{
        request_id: 0x12345678,
        version: "1.2.3",
        config_id: 0xDEADBEEF
      }

      {:ok, encoded} = IdentityResponse.encode(response)

      # Type (0x01) + request_id (little endian) + major + minor + patch + config_id (little endian)
      assert encoded == <<0x01, 0x78, 0x56, 0x34, 0x12, 0x01, 0x02, 0x03, 0xEF, 0xBE, 0xAD, 0xDE>>
    end

    test "decode decodes valid message" do
      binary = <<0x01, 0x78, 0x56, 0x34, 0x12, 0x01, 0x02, 0x03, 0xEF, 0xBE, 0xAD, 0xDE>>
      {:ok, decoded} = IdentityResponse.decode(binary)

      assert decoded == %IdentityResponse{
               request_id: 0x12345678,
               version: "1.2.3",
               config_id: 0xDEADBEEF
             }
    end

    test "decode returns error for invalid message type" do
      assert IdentityResponse.decode(
               <<0x00, 0x78, 0x56, 0x34, 0x12, 0x01, 0x02, 0x03, 0xEF, 0xBE, 0xAD, 0xDE>>
             ) == {:error, :invalid_message}
    end

    test "decode returns error for incomplete message" do
      assert IdentityResponse.decode(<<0x01, 0x78, 0x56>>) == {:error, :invalid_message}
    end

    test "roundtrip encode/decode" do
      original = %IdentityResponse{
        request_id: 0x12345678,
        version: "1.2.3",
        config_id: 0xDEADBEEF
      }

      {:ok, encoded} = IdentityResponse.encode(original)
      {:ok, decoded} = IdentityResponse.decode(encoded)

      assert decoded == original
    end
  end

  describe "Configure" do
    test "type returns 0x02" do
      assert Configure.type() == 0x02
    end

    test "encode encodes all fields correctly" do
      configure = %Configure{
        config_id: 0x12345678,
        total_parts: 0x05,
        part_number: 0x02,
        input_type: :analog,
        pin: 0x0A,
        sensitivity: 0x64
      }

      {:ok, encoded} = Configure.encode(configure)

      # Type (0x02) + config_id (little endian) + total_parts + part_number + input_type (0x00 = analog) + pin + sensitivity
      assert encoded == <<0x02, 0x78, 0x56, 0x34, 0x12, 0x05, 0x02, 0x00, 0x0A, 0x64>>
    end

    test "decode decodes valid message" do
      binary = <<0x02, 0x78, 0x56, 0x34, 0x12, 0x05, 0x02, 0x00, 0x0A, 0x64>>
      {:ok, decoded} = Configure.decode(binary)

      assert decoded == %Configure{
               config_id: 0x12345678,
               total_parts: 0x05,
               part_number: 0x02,
               input_type: :analog,
               pin: 0x0A,
               sensitivity: 0x64
             }
    end

    test "decode returns error for invalid message type" do
      assert Configure.decode(<<0x01, 0x78, 0x56, 0x34, 0x12, 0x05, 0x02, 0x01, 0x0A, 0x64>>) ==
               {:error, :invalid_message}
    end

    test "decode returns error for incomplete message" do
      assert Configure.decode(<<0x02, 0x78, 0x56>>) == {:error, :invalid_message}
    end

    test "roundtrip encode/decode" do
      original = %Configure{
        config_id: 0x12345678,
        total_parts: 0x05,
        part_number: 0x02,
        input_type: :analog,
        pin: 0x0A,
        sensitivity: 0x64
      }

      {:ok, encoded} = Configure.encode(original)
      {:ok, decoded} = Configure.decode(encoded)

      assert decoded == original
    end
  end

  describe "ConfigurationStored" do
    test "type returns 0x03" do
      assert ConfigurationStored.type() == 0x03
    end

    test "encode encodes config_id correctly" do
      stored = %ConfigurationStored{config_id: 0x12345678}
      {:ok, encoded} = ConfigurationStored.encode(stored)

      # Type (0x03) + config_id (little endian)
      assert encoded == <<0x03, 0x78, 0x56, 0x34, 0x12>>
    end

    test "decode decodes valid message" do
      binary = <<0x03, 0x78, 0x56, 0x34, 0x12>>
      {:ok, decoded} = ConfigurationStored.decode(binary)

      assert decoded == %ConfigurationStored{config_id: 0x12345678}
    end

    test "decode returns error for invalid message type" do
      assert ConfigurationStored.decode(<<0x02, 0x78, 0x56, 0x34, 0x12>>) ==
               {:error, :invalid_message}
    end

    test "decode returns error for incomplete message" do
      assert ConfigurationStored.decode(<<0x03, 0x78, 0x56>>) == {:error, :invalid_message}
    end

    test "roundtrip encode/decode" do
      original = %ConfigurationStored{config_id: 0xDEADBEEF}
      {:ok, encoded} = ConfigurationStored.encode(original)
      {:ok, decoded} = ConfigurationStored.decode(encoded)

      assert decoded == original
    end
  end

  describe "ConfigurationError" do
    test "type returns 0x04" do
      assert ConfigurationError.type() == 0x04
    end

    test "encode encodes config_id correctly" do
      error = %ConfigurationError{config_id: 0x12345678}
      {:ok, encoded} = ConfigurationError.encode(error)

      # Type (0x04) + config_id (little endian)
      assert encoded == <<0x04, 0x78, 0x56, 0x34, 0x12>>
    end

    test "decode decodes valid message" do
      binary = <<0x04, 0x78, 0x56, 0x34, 0x12>>
      {:ok, decoded} = ConfigurationError.decode(binary)

      assert decoded == %ConfigurationError{config_id: 0x12345678}
    end

    test "decode returns error for invalid message type" do
      assert ConfigurationError.decode(<<0x03, 0x78, 0x56, 0x34, 0x12>>) ==
               {:error, :invalid_message}
    end

    test "decode returns error for incomplete message" do
      assert ConfigurationError.decode(<<0x04, 0x78, 0x56>>) == {:error, :invalid_message}
    end

    test "roundtrip encode/decode" do
      original = %ConfigurationError{config_id: 0xDEADBEEF}
      {:ok, encoded} = ConfigurationError.encode(original)
      {:ok, decoded} = ConfigurationError.decode(encoded)

      assert decoded == original
    end
  end

  describe "InputValue" do
    test "type returns 0x05" do
      assert InputValue.type() == 0x05
    end

    test "encode encodes positive value correctly" do
      input = %InputValue{pin: 0x0A, value: 0x1234}
      {:ok, encoded} = InputValue.encode(input)

      # Type (0x05) + pin + value (little endian signed)
      assert encoded == <<0x05, 0x0A, 0x34, 0x12>>
    end

    test "encode encodes negative value correctly" do
      input = %InputValue{pin: 0x0A, value: -1}
      {:ok, encoded} = InputValue.encode(input)

      # -1 in two's complement little endian: 0xFF, 0xFF
      assert encoded == <<0x05, 0x0A, 0xFF, 0xFF>>
    end

    test "decode decodes positive value" do
      binary = <<0x05, 0x0A, 0x34, 0x12>>
      {:ok, decoded} = InputValue.decode(binary)

      assert decoded == %InputValue{pin: 0x0A, value: 0x1234}
    end

    test "decode decodes negative value" do
      # -1 in two's complement little endian: 0xFF, 0xFF
      binary = <<0x05, 0x0A, 0xFF, 0xFF>>
      {:ok, decoded} = InputValue.decode(binary)

      assert decoded == %InputValue{pin: 0x0A, value: -1}
    end

    test "decode returns error for invalid message type" do
      assert InputValue.decode(<<0x04, 0x0A, 0x34, 0x12>>) == {:error, :invalid_message}
    end

    test "decode returns error for incomplete message" do
      assert InputValue.decode(<<0x05, 0x0A>>) == {:error, :invalid_message}
    end

    test "roundtrip encode/decode with positive value" do
      original = %InputValue{pin: 0x0A, value: 0x1234}
      {:ok, encoded} = InputValue.encode(original)
      {:ok, decoded} = InputValue.decode(encoded)

      assert decoded == original
    end

    test "roundtrip encode/decode with negative value" do
      original = %InputValue{pin: 0x0A, value: -32768}
      {:ok, encoded} = InputValue.encode(original)
      {:ok, decoded} = InputValue.decode(encoded)

      assert decoded == original
    end
  end

  describe "Heartbeat" do
    test "type returns 0x06" do
      assert Heartbeat.type() == 0x06
    end

    test "encode encodes message correctly" do
      heartbeat = %Heartbeat{}
      {:ok, encoded} = Heartbeat.encode(heartbeat)

      assert encoded == <<0x06>>
    end

    test "decode decodes valid message" do
      binary = <<0x06>>
      {:ok, decoded} = Heartbeat.decode(binary)

      assert decoded == %Heartbeat{}
    end

    test "decode returns error for invalid message type" do
      assert Heartbeat.decode(<<0x05>>) == {:error, :invalid_message}
    end

    test "decode returns error for empty message" do
      assert Heartbeat.decode(<<>>) == {:error, :invalid_message}
    end

    test "roundtrip encode/decode" do
      original = %Heartbeat{}
      {:ok, encoded} = Heartbeat.encode(original)
      {:ok, decoded} = Heartbeat.decode(encoded)

      assert decoded == original
    end
  end

  describe "Message.decode/1" do
    alias TswIo.Serial.Protocol.Message

    test "decodes IdentityRequest" do
      binary = <<0x00, 0x78, 0x56, 0x34, 0x12>>
      {:ok, decoded} = Message.decode(binary)

      assert decoded == %IdentityRequest{request_id: 0x12345678}
    end

    test "decodes IdentityResponse" do
      binary = <<0x01, 0x78, 0x56, 0x34, 0x12, 0x01, 0x02, 0x03, 0xEF, 0xBE, 0xAD, 0xDE>>
      {:ok, decoded} = Message.decode(binary)

      assert decoded == %IdentityResponse{
               request_id: 0x12345678,
               version: "1.2.3",
               config_id: 0xDEADBEEF
             }
    end

    test "decodes Configure" do
      binary = <<0x02, 0x78, 0x56, 0x34, 0x12, 0x05, 0x02, 0x00, 0x0A, 0x64>>
      {:ok, decoded} = Message.decode(binary)

      assert decoded == %Configure{
               config_id: 0x12345678,
               total_parts: 0x05,
               part_number: 0x02,
               input_type: :analog,
               pin: 0x0A,
               sensitivity: 0x64
             }
    end

    test "decodes ConfigurationStored" do
      binary = <<0x03, 0x78, 0x56, 0x34, 0x12>>
      {:ok, decoded} = Message.decode(binary)

      assert decoded == %ConfigurationStored{config_id: 0x12345678}
    end

    test "decodes ConfigurationError" do
      binary = <<0x04, 0x78, 0x56, 0x34, 0x12>>
      {:ok, decoded} = Message.decode(binary)

      assert decoded == %ConfigurationError{config_id: 0x12345678}
    end

    test "decodes InputValue" do
      binary = <<0x05, 0x0A, 0x34, 0x12>>
      {:ok, decoded} = Message.decode(binary)

      assert decoded == %InputValue{pin: 0x0A, value: 0x1234}
    end

    test "decodes InputValue with negative value" do
      binary = <<0x05, 0x0A, 0xFF, 0xFF>>
      {:ok, decoded} = Message.decode(binary)

      assert decoded == %InputValue{pin: 0x0A, value: -1}
    end

    test "decodes Heartbeat" do
      binary = <<0x06>>
      {:ok, decoded} = Message.decode(binary)

      assert decoded == %Heartbeat{}
    end

    test "returns error for unknown message type" do
      binary = <<0xFF>>
      assert Message.decode(binary) == {:error, :unknown_message_type}
    end

    test "returns error for insufficient data" do
      assert Message.decode(<<>>) == {:error, :insufficient_data}
    end

    test "returns error for invalid input" do
      assert Message.decode(nil) == {:error, :invalid_input}
      assert Message.decode(123) == {:error, :invalid_input}
    end

    test "roundtrip through Message.decode for all message types" do
      messages = [
        %IdentityRequest{request_id: 0x12345678},
        %IdentityResponse{
          request_id: 0x12345678,
          version: "1.2.3",
          config_id: 0xDEADBEEF
        },
        %Configure{
          config_id: 0x12345678,
          total_parts: 0x05,
          part_number: 0x02,
          input_type: :analog,
          pin: 0x0A,
          sensitivity: 0x64
        },
        %ConfigurationStored{config_id: 0x12345678},
        %ConfigurationError{config_id: 0x12345678},
        %InputValue{pin: 0x0A, value: 0x1234},
        %Heartbeat{}
      ]

      for message <- messages do
        module = message.__struct__
        {:ok, encoded} = module.encode(message)
        {:ok, decoded} = Message.decode(encoded)

        assert decoded == message
      end
    end
  end
end
