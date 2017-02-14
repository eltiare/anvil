defmodule AuthRequests do

  # API and helpers
  def start_link() do
    self() |> FastWorker.start_link()
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

  defp listener(pid, workers) do
    listener(pid, workers, 0)
  end

  defp listener(pid, workers, counter) do
    receive do
      { :task_started, id } ->
        IO.puts "Started #{workers[id]}! (#{counter})"
        listener(pid, workers, counter + 1)
      { :task_failed, id } ->
        IO.puts "Failed #{workers[id]}!"
        listener(pid, workers, counter + 1)
      :done -> true
    end
  end

  # Work support
  def request_auth(domain) do
    request_auth(domain, "html")
  end

  def request_auth(domain, html_dir) do
    IO.puts "Domain working: #{domain}"
    :timer.sleep(5000)
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


end
