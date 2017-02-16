defmodule AuthRequests do

  # API
  def start_link(process, opts // []) when is_pid(process) do
    GenServer.start_link(__MODULE__, process)
  end

  def start_link(opts // []) do
    self() |> start_link(opts)
  end

  def add_task(pid, fun) when is_function(fun) do
    GenServer.call(pid, { :add_task, fun })
  end

  def add_task(pid, module, method, args) do
    GenServer.call(pid, { :add_task, module, method, args })
  end

  def do_work(pid) do
    GenServer.cast(pid, :do_work)
  end

  def start_auths(pid, domains) do
    workers = Enum.map(domains, fn(domain) ->
      {
        FastWorker.add_task(pid, __MODULE__, :request_auth, [domain]),
        domain
      }
    end) |> Enum.into(%{})
    FastWorker.do_work(pid)
    listener(pid, workers)
  end

  # Server
  def init(callback_pid, opts // []) do
    pid = self() |> FastWorker.start_link(opts)
    %{ worker: pid, callback: callback_pid , tasks: %{}}
  end

  def handle_call({:add_task, fun }, _caller, state) do
    FastWorker.add_task(state[:worker], fun)
    |> finish_add_task(state)
  end

  def handle_call({:add_task, mod, fun, args}, _caller, state) do
    FastWorker.add_task(state[:worker], mod, fun, args)
    |> finish_add_task(state)
  end

  defp finish_add_task(id, state) do
    { :reply, id, { state | tasks: state[:tasks] |> Map.put(id, :waiting) } }
  end

  # Server Callbacks from FastWorker
  def handle_cast({ :task_start, id } = msg, state) do
    GenServer.cast(state[:callback], msg)
    update_task_state(id, :working, state)
  end

  def handle_cast({ :task_done, id, val } = msg), state) do
    GenServer.cast(state[:callback, msg])
    update_task_state(id, {:done, val}, state)
  end

  def handle_cast({ :task_fail, id, reason, count } = msg, state) do
    GenServer.cast(state[:callback], msg)
    update_task_state(id, { :fail, reason, count}, state)
  end

  def handle_cast(:all_done = msg, state) do
    GenServer.cast(state[:callback], { msg, state[:tasks] })
    { :noreply, state }
  end

  defp update_task_state(id, val, state) do
    { :noreply, { state | tasks: state[:tasks] |> Map.put(id, val) } }
  end

  # Work support

  def request_auth(domain, html_dir \\ "html") do
    IO.puts "Domain working: #{domain}"
    :timer.sleep(5000)
    true
    # case NginxDockerCerts.resource_request("new-authz", identifier: [ type: "dns", value: domain ]) do
    #   { :ok, %HTTPoison.Response{ body: body } } ->
    #     # TODO: only HTTP auth for now, add others later (?)
    #     le_response = JSON.decode!(body)
    #     challenge = le_response["challenges"]
    #       |> Enum.find( fn(%{ "type" => type }) -> type == "http-01" end )
    #     challenge_response = "#{challenge["token"]}.#{NginxDockerCerts.get_thumbprint()}"
    #     File.write!("#{html_dir}/#{challenge["token"]}", challenge_response)
    #     IO.inspect challenge
    #     { :ok, challenge }
    #     # TODO: Extract this to another step/function.
    #     # IO.gets "Files written. Please press enter when ready"
    #     # case send_request(challenge["uri"],
    #     #                   resource: "challenge",
    #     #                   keyAuthorization: challenge_response) do
    #     #   { :ok, %HTTPoison.Response{ status_code: 202 } } ->
    #     #     complete_authorize(challenge["uri"])
    #     #   { _, resp } -> err(inspect resp)
    #     # end
    #   { _ , resp } -> { :error, resp }
    # end
  end

  # Server



end
