defmodule Config do

  def start_link(map) when is_map(map) do
    Agent.start_link(fn -> map end, name: __MODULE__)
  end

  def put(key, value) do
    list = String.split(key, ".")
    Agent.update(__MODULE__, &put_in(&1, list, value))
  end

  def merge(map)  do
    Agent.update(__MODULE__, &Map.merge(&1, map))
  end

  def get(key) do
    list = String.split(key, ".")
    Agent.get(__MODULE__, &get_in(&1, list))
  end

  def get do
    Agent.get(__MODULE__, fn(map) -> map end)
  end

  def get_or_put(key, default_value) do
    get(key) || ( put(key, default_value) && default_value )
  end

end
