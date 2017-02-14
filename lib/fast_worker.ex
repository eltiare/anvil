defmodule FastWorker do

  use GenServer

  # API

  # lister = pid of process that is listening to events
  # opts = [
  #   max_workers: (num),
  #   max_fails: (num)
  # ]
  def start_link(listener, opts \\ []) do
    GenServer.start_link(__MODULE__, [listener, Enum.into(opts, %{})])
  end

  def add_task(server_pid, fun) when is_function(fun) do
    GenServer.call(server_pid, { :add_task, fun })
  end

  def add_task(server_pid, module, method, args) do
    GenServer.call(server_pid, { :add_task, module, method, args })
  end

  def do_work(server_pid) when is_pid(server_pid) do
    GenServer.cast(server_pid, :do_work)
  end

  def get_state(server_pid) when is_pid(server_pid) do
    GenServer.call(server_pid, :get_state)
  end

  # Server callbacks
  def init([listener | opts]) do
    Process.flag(:trap_exit, true)
    {
      :ok,
      %{
        worker_map: %{},
        waiting_workers: [],
        active_workers: %{},
        failed_workers: %{},
        max_workers: opts[:max_workers] || 100,
        max_fails: opts[:max_fails] || 25,
        listener: listener
      }
    }
  end

  def handle_call(:get_state, _caller, state) do
    { :reply, state, state }
  end

  def handle_call({:add_task, fun}, _caller, state) when is_function(fun) do
    { id, state } = add_worker({fun}, state)
    { :reply, id, state }
  end

  def handle_call({:add_task, module, fun_name, args}, _caller, state) do
    { id, state } = add_worker({ module, fun_name, args }, state)
    { :reply, id, state }
  end

  def handle_cast(:do_work, state) do
    { :noreply, check_workers(state) }
  end

  # Get the value
  def handle_info({ref, value}, state) do
    # IO.puts "Handle info, value"
    # IO.inspect ref
    # IO.inspect value
    # IO.inspect state
    { :noreply, state }
  end

  # General handler
  def handle_info(msg, state) do
    # IO.puts "Handle info, general"
    # IO.inspect msg
    # IO.inspect state
    { :noreply, state }
  end

  # Helpers
  defp add_worker(tuple, state) do
    id = unique_id(state[:worker_map])
    state = Map.merge(state, %{
        worker_map: state[:worker_map] |> Map.put(id, tuple),
        waiting_workers: [ id | state[:waiting_workers] ]
      })
    { id, state }
  end

  defp check_workers(state) do
    IO.inspect state
    num_working = state[:active_workers] |> Enum.into([]) |> length()
    num_new_workers = state[:max_workers] - num_working
    new_workers = state[:waiting_workers]
    |> Enum.reverse
    |> extract_worker_ids(num_new_workers)
    |> Enum.map(fn(id) ->
        task = case state[:worker_map][id] do
          { fun } ->  Task.async(fun)
          { mod, fun, args } -> Task.async(mod, fun, args)
        end
        send(state[:listener], { :task_started, id })
        { id, task }
      end)
    |> Enum.into(%{})
    IO.inspect state[:waiting_workers]
    %{ state |
      active_workers: state[:active_workers] |> Map.merge(new_workers) ,
      waiting_workers: state[:waiting_workers] -- Map.keys(new_workers)
    }
  end

  defp extract_worker_ids(list, upto, accumulator \\[])
  defp extract_worker_ids([id | tail], upto, accumulator)  do
    accumulator = [ id | accumulator ]
    if length(accumulator) >= upto, do: extract_worker_ids([], 0, accumulator),
      else: extract_worker_ids(tail, upto, accumulator)
  end
  defp extract_worker_ids([], _upto, accumulator) do
    accumulator |> Enum.reverse
  end

  defp unique_id(map) do
    id = random_id()
    if map[id], do: unique_id(map), else: id
  end

  defp random_id() do
    3 + :rand.uniform(15) |> random_string
  end

  defp random_string(len) do
    :crypto.strong_rand_bytes(len) |> Base.encode64 |> binary_part(0, len)
  end

end
