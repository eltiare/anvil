defmodule Utils do

  def valuesFor(list, key, accumulator \\ [])

  def valuesFor([next | rest], key, accumulator) do
    if elem(next, 0) == key do
      valuesFor(rest, key, accumulator ++ [elem(next, 1)])
    else
      valuesFor(rest, key, accumulator)
    end
  end

  def valuesFor([], _key, accumulator) do
    accumulator
  end

  def le_b64(map) when is_map(map) or is_list(map) do
    map |> JSON.encode! |> le_b64
  end

  def le_b64(str) when is_binary(str) do
    Base.url_encode64(str, padding: false)
  end

  def delete_all(list, val) when is_list(list) do
    delete_all(list, val, []) |> Enum.reverse
  end

  defp delete_all([h|[]], val, end_list) do
    if h === val, do: end_list, else: [h|end_list]
  end

  defp delete_all([h|t], val, end_list) do
    if h === val, do: delete_all(t, val, end_list),
        else: delete_all(t, val, [h|end_list])
  end

end
