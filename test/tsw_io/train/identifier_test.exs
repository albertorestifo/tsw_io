defmodule TswIo.Train.IdentifierTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TswIo.Simulator.Client
  alias TswIo.Train.Identifier

  @base_url "http://localhost:31270"
  @api_key "test-api-key"

  setup :verify_on_exit!

  describe "common_prefix/1" do
    test "returns empty string for empty list" do
      assert Identifier.common_prefix([]) == ""
    end

    test "returns the single string when list has one element" do
      assert Identifier.common_prefix(["BR_Class_66"]) == "BR_Class_66"
    end

    test "finds common prefix of two identical strings" do
      assert Identifier.common_prefix(["BR_Class_66", "BR_Class_66"]) == "BR_Class_66"
    end

    test "finds common prefix of strings with same beginning" do
      assert Identifier.common_prefix(["BR_Class_66_DB", "BR_Class_66_Freightliner"]) ==
               "BR_Class_66"
    end

    test "finds common prefix across multiple strings" do
      strings = [
        "BR_Class_66_DB_Cargo",
        "BR_Class_66_Freightliner",
        "BR_Class_66_GBRF"
      ]

      assert Identifier.common_prefix(strings) == "BR_Class_66"
    end

    test "returns empty string when no common prefix exists" do
      assert Identifier.common_prefix(["ABC", "XYZ"]) == ""
    end

    test "handles strings of different lengths" do
      assert Identifier.common_prefix(["AB", "ABCD", "ABCDEF"]) == "AB"
    end

    test "handles unicode characters" do
      assert Identifier.common_prefix(["Zürich_Train_A", "Zürich_Train_B"]) == "Zürich_Train"
    end

    test "strips trailing non-alphanumeric characters" do
      # Common prefix should not end with underscore or other non-alphanumeric chars
      assert Identifier.common_prefix(["BR_Class_66_DB", "BR_Class_66_Freightliner"]) ==
               "BR_Class_66"
    end

    test "strips multiple trailing non-alphanumeric characters" do
      assert Identifier.common_prefix(["Train__A", "Train__B"]) == "Train"
    end

    test "handles prefix that is entirely alphanumeric" do
      assert Identifier.common_prefix(["ABC123X", "ABC123Y"]) == "ABC123"
    end
  end

  describe "derive_from_formation/1" do
    test "returns identifier from formation with multiple cars" do
      client = Client.new(@base_url, @api_key)

      # Mock formation length
      expect(Req, :request, fn _req, opts ->
        assert opts[:url] == "/get/CurrentFormation.FormationLength"

        {:ok,
         %Req.Response{
           status: 200,
           body: %{"Result" => "Success", "Values" => %{"FormationLength" => 3}}
         }}
      end)

      # Mock object classes - these are called async so we need to expect multiple times
      expect(Req, :request, 3, fn _req, opts ->
        cond do
          opts[:url] == "/get/CurrentFormation/0.ObjectClass" ->
            {:ok,
             %Req.Response{
               status: 200,
               body: %{"Result" => "Success", "Values" => %{"ObjectClass" => "BR_Class_66_Loco"}}
             }}

          opts[:url] == "/get/CurrentFormation/1.ObjectClass" ->
            {:ok,
             %Req.Response{
               status: 200,
               body: %{
                 "Result" => "Success",
                 "Values" => %{"ObjectClass" => "BR_Class_66_Wagon1"}
               }
             }}

          opts[:url] == "/get/CurrentFormation/2.ObjectClass" ->
            {:ok,
             %Req.Response{
               status: 200,
               body: %{
                 "Result" => "Success",
                 "Values" => %{"ObjectClass" => "BR_Class_66_Wagon2"}
               }
             }}
        end
      end)

      assert {:ok, identifier} = Identifier.derive_from_formation(client)
      assert identifier == "BR_Class_66"
    end

    test "returns error for empty formation" do
      client = Client.new(@base_url, @api_key)

      expect(Req, :request, fn _req, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"Result" => "Success", "Values" => %{"FormationLength" => 0}}
         }}
      end)

      assert {:error, :empty_formation} = Identifier.derive_from_formation(client)
    end

    test "returns error for single car formation" do
      client = Client.new(@base_url, @api_key)

      expect(Req, :request, fn _req, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"Result" => "Success", "Values" => %{"FormationLength" => 1}}
         }}
      end)

      assert {:error, :single_car_formation} = Identifier.derive_from_formation(client)
    end

    test "returns error when formation length request fails" do
      client = Client.new(@base_url, @api_key)

      expect(Req, :request, fn _req, _opts ->
        {:ok, %Req.Response{status: 500, body: %{"error" => "Internal error"}}}
      end)

      assert {:error, {:http_error, 500, _}} = Identifier.derive_from_formation(client)
    end

    test "succeeds with partial results if at least 2 object classes retrieved" do
      client = Client.new(@base_url, @api_key)

      expect(Req, :request, fn _req, opts ->
        assert opts[:url] == "/get/CurrentFormation.FormationLength"

        {:ok,
         %Req.Response{
           status: 200,
           body: %{"Result" => "Success", "Values" => %{"FormationLength" => 3}}
         }}
      end)

      # One request fails, two succeed - should still work
      expect(Req, :request, 3, fn _req, opts ->
        cond do
          opts[:url] == "/get/CurrentFormation/0.ObjectClass" ->
            {:ok,
             %Req.Response{
               status: 200,
               body: %{"Result" => "Success", "Values" => %{"ObjectClass" => "Train_Type_A1"}}
             }}

          opts[:url] == "/get/CurrentFormation/1.ObjectClass" ->
            {:error, %Mint.TransportError{reason: :timeout}}

          opts[:url] == "/get/CurrentFormation/2.ObjectClass" ->
            {:ok,
             %Req.Response{
               status: 200,
               body: %{"Result" => "Success", "Values" => %{"ObjectClass" => "Train_Type_A2"}}
             }}
        end
      end)

      assert {:ok, identifier} = Identifier.derive_from_formation(client)
      assert identifier == "Train_Type_A"
    end

    test "returns error when fewer than 2 object classes retrieved" do
      client = Client.new(@base_url, @api_key)

      expect(Req, :request, fn _req, opts ->
        assert opts[:url] == "/get/CurrentFormation.FormationLength"

        {:ok,
         %Req.Response{
           status: 200,
           body: %{"Result" => "Success", "Values" => %{"FormationLength" => 3}}
         }}
      end)

      # Two requests fail, only one succeeds - should fail
      expect(Req, :request, 3, fn _req, opts ->
        cond do
          opts[:url] == "/get/CurrentFormation/0.ObjectClass" ->
            {:ok,
             %Req.Response{
               status: 200,
               body: %{"Result" => "Success", "Values" => %{"ObjectClass" => "Train_Type_A1"}}
             }}

          opts[:url] == "/get/CurrentFormation/1.ObjectClass" ->
            {:error, %Mint.TransportError{reason: :timeout}}

          opts[:url] == "/get/CurrentFormation/2.ObjectClass" ->
            {:error, %Mint.TransportError{reason: :timeout}}
        end
      end)

      assert {:error, :insufficient_formation_data} = Identifier.derive_from_formation(client)
    end
  end
end
