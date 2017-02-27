defmodule AcmeClient do

  use GenServer
  alias Task.Supervisor

  # API
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts |> Enum.into(%{}))
  end

  defp collect_values, do: collect_values(%{})
  defp collect_values(accumulator) do
    receive do
      { :task_done, { id, value } } ->
        accumulator |> Map.put(id, value) |> collect_values
      :all_done -> accumulator
    end
  end

  def register(pid, contacts) do
    GenServer.call(pid, { :register, contacts })
  end

  def authorize_domains(pid, domains, opts \\ []) do
    opts = opts |> Enum.into(%{})
    html_dir = opts["html_dir"] || "html"
    GenServer.call(pid, { :map_requests, :request_auth, domains })
    start_results = collect_values()
    for { domain, result } <- start_results do
      case result do
        { :ok, { challenge, response } } ->
          File.write!("#{html_dir}/#{challenge["token"]}", response)
        { :error, _reason, msg } -> IO.puts("There was an error with #{domain}: #{msg}")
      end
    end
    if aw = opts["auth_wait"] do
      IO.puts "Waiting for #{aw} ms"
      aw |> :timer.sleep
    end
    filter = fn({_k,v}) -> elem(v, 0) == :ok end
    finish_domains = Enum.filter(start_results, filter) |> Enum.into(%{})
    arg_callback = fn(domain) ->
      { :ok, web_response } = finish_domains[domain]
      [ web_response ]
    end
    GenServer.call(pid, { :map_requests, :finish_auth, Map.keys(finish_domains), arg_callback })
    collect_values()
  end

  def request_certificate(pid, cert_opts) do
    GenServer.call(pid, { :request_certificate, cert_opts })
  end

  # Server
  def init(opts) do
    sup_opts = [
      restart: :transient,
      max_restarts: opts[:max_restarts] || 10,
      max_seconds: opts[:max_seconds] || 150
    ]
    { :ok, sup } = Supervisor.start_link(sup_opts)
    # Start the worker with appropriate options
    header = make_header(opts)
    worker_opts =  Map.take(opts, ["api_location", :endpoints, :key]) |> Map.merge(%{
        header: header,
        thumbprint: make_thumbprint(header)
      })
    { :ok, worker } = AcmeWorkers.start_link(worker_opts)
    { :ok, %{ sup: sup, worker: worker, opts: opts } |> reset_state }
  end

  defp reset_state(state) do
    state |> Map.merge(%{ tasks: %{}, caller: nil, values: %{} })
  end

  # From the erlang docs:
  # Key = public_key:pem_entry_decode(RSAEntry, "abcd1234").
  # 'RSAPrivateKey'{version = 'two-prime',
  #  modulus = 1112355156729921663373...2737107,
  #  publicExponent = 65537,
  #  privateExponent = 58064406231183...2239766033,
  #  prime1 = 11034766614656598484098...7326883017,
  #  prime2 = 10080459293561036618240...77738643771,
  #  exponent1 = 77928819327425934607...22152984217,
  #  exponent2 = 36287623121853605733...20588523793,
  #  coefficient = 924840412626098444...41820968343,
  #  otherPrimeInfos = asn1_NOVALUE}
  defp make_header(opts) do
    # Look into asn1 decoders for detection of key sizes. There's one in
    # effin JavaScript, should be one for Erlang/Elixir
    modulus = case opts[:key_size] do
      ks when ks in [nil, "2048", 2048] -> <<elem(opts[:key], 2)::2048>>
      ks when ks in ["4096", 4096] -> <<elem(opts[:key], 2)::4096>>
    end |> le_b64
    exponent = <<elem(opts[:key], 3)::24>> |> le_b64
    %{
      alg: "RS256",
      jwk: [ e: exponent, kty: "RSA", n: modulus ]
    }
  end

  defp make_thumbprint(header) do
    jwk = header[:jwk] |> JSON.encode!
    :crypto.hash(:sha256, jwk) |> le_b64
  end

  def handle_call(:reset, _caller, state) do
    state = reset_state(state)
    { :reply, state,  state }
  end

  def handle_call({ :register, contacts }, _caller, state) do
    AcmeWorkers.register(state[:worker], contacts)
    { :reply, true, state }
  end

  def handle_call({ :map_requests, f, l }, caller, state) do
    map_requests({ :map_requests, f, l, [] }, caller, state)
  end

  def handle_call({ :map_requests, _f, _l, _a } = tuple, caller, state) do
    map_requests(tuple, caller, state)
  end

  def handle_call({:request_certificate, cert_opts}, _caller, state) do
    response = AcmeWorkers.request_cert(state[:worker], cert_opts)
    { :reply, response, state }
  end

  defp map_requests({ :map_requests, function, list, args }, caller, state) do
    task_refs = for item <- list do
      pass_args = cond do
        is_function(args) -> args.(item)
        is_list(args) -> args
      end
      task = Supervisor.async(state[:sup], AcmeWorkers, function, [ state[:worker], item | pass_args ])
      { task.ref, { task, item } }
    end |> Enum.into(%{})
    state = %{ reset_state(state) | tasks: Map.merge(state[:tasks], task_refs), caller: caller }
    { :reply, state, state }
  end

  def handle_info({ref, value}, state) do
    { _, id } = state[:tasks][ref]
    { pid, _ } = state[:caller]
    send(pid, { :task_done, { id, value }})
    { :noreply, state }
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, state) do
    state = %{ state | tasks: state[:tasks] |> Map.delete(ref) }
    if state[:tasks] |> Map.keys() |> length() == 0 do
      state[:caller] |> elem(0) |> send(:all_done)
    end
    { :noreply, state }
  end

  # TODO: handle errors

  # UTILS

  def le_b64(map) when is_map(map) or is_list(map) do
    map |> JSON.encode! |> le_b64
  end

  def le_b64(str) when is_binary(str) do
    Base.url_encode64(str, padding: false)
  end

  def decode_key(key) do
    :public_key.pem_decode(key) |> List.first() |> :public_key.pem_entry_decode()
  end

end
