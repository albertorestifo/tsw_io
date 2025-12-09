defmodule TswIo.Train.Identifier do
  @moduledoc """
  Generates train identifiers from formation ObjectClass values.

  The identifier is the common prefix among all ObjectClass values
  in the current formation, providing a stable way to identify
  specific train types across sessions.
  """

  alias TswIo.Simulator.Client

  @doc """
  Derives train identifier from the current formation in the simulator.

  Returns the common prefix of all ObjectClass values as a string.
  Fetches object classes in parallel using async tasks.
  """
  @spec derive_from_formation(Client.t()) :: {:ok, String.t()} | {:error, term()}
  def derive_from_formation(%Client{} = client) do
    with {:ok, length} <- Client.get_int(client, "CurrentFormation.FormationLength"),
         {:ok, object_classes} <- get_object_classes(client, length) do
      {:ok, common_prefix(object_classes)}
    end
  end

  @doc """
  Finds the common prefix among a list of strings.
  """
  @spec common_prefix([String.t()]) :: String.t()
  def common_prefix([]), do: ""
  def common_prefix([single]), do: single

  def common_prefix([first | rest]) do
    prefix =
      Enum.reduce(rest, first, fn string, acc ->
        find_common_prefix(acc, string)
      end)

    strip_trailing_non_alphanumeric(prefix)
  end

  # Private functions

  defp get_object_classes(_client, 0), do: {:error, :empty_formation}
  defp get_object_classes(_client, 1), do: {:error, :single_car_formation}

  defp get_object_classes(%Client{} = client, length) when length > 1 do
    # Fetch all object classes in parallel using async tasks
    tasks =
      0..(length - 1)
      |> Enum.map(fn index ->
        Task.async(fn ->
          Client.get_string(client, "CurrentFormation/#{index}.ObjectClass")
        end)
      end)

    # Collect results, filtering out errors
    results =
      tasks
      |> Task.await_many(:timer.seconds(5))
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, class} -> class end)

    # We need at least 2 results to compute a meaningful common prefix
    if length(results) >= 2 do
      {:ok, results}
    else
      {:error, :insufficient_formation_data}
    end
  end

  defp find_common_prefix(s1, s2) do
    s1_chars = String.graphemes(s1)
    s2_chars = String.graphemes(s2)

    s1_chars
    |> Enum.zip(s2_chars)
    |> Enum.take_while(fn {a, b} -> a == b end)
    |> Enum.map(fn {a, _} -> a end)
    |> Enum.join()
  end

  defp strip_trailing_non_alphanumeric(string) do
    String.replace(string, ~r/[^a-zA-Z0-9]+$/, "")
  end
end
