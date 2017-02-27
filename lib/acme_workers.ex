defmodule AcmeWorkers do

  def start_link(map) when is_map(map) do
     Agent.start_link(fn -> map end)
  end

  def register(agent, contacts) do
    case resource_request(agent, "new-reg", contact: contacts ) do
      { :ok, %HTTPoison.Response{ status_code: 201, headers: headers }} ->
        location = Enum.into(headers, %{})["Location"]
        filter = fn({name,_val}) -> name == "Link" end
        mapper = fn({_name,val}) -> val end
        tos_link = headers |> Enum.filter_map(filter, mapper)
          |> Enum.find(fn(str) -> String.match?(str, ~r/terms-of-service/) end)
          |> String.replace(~r/.*<([^>]+)>.*/, "\\1")
        IO.puts "Accepting terms at #{tos_link}"
        case send_request(agent, location, resource: "reg", agreement: tos_link) do
          { :ok, %HTTPoison.Response{ status_code: 202 } } ->
            { :ok }
          { _, response } ->
            { :error, :registration, "\nRegistration is successful but there was a problem with the TOS:\n\n#{inspect response}" }
        end
      { _, response } ->
        { :error, :unknown, "\nThere was an error processing the request:\n\n#{ inspect response }\n" }
    end
  end

  def request_auth(agent, domain) do
    case resource_request(agent, "new-authz", identifier: [ type: "dns", value: domain ]) do
      { :ok, %HTTPoison.Response{ body: body } } ->
        # TODO: only HTTP auth for now, add others later (?)
        le_response = JSON.decode!(body)
        challenge = le_response["challenges"]
          |> Enum.find( fn(%{ "type" => type }) -> type == "http-01" end )
        challenge_response = "#{challenge["token"]}.#{get(agent, :thumbprint)}"
        { :ok, { challenge, challenge_response } }
      { _ , resp } -> { :error, :unknown, resp }
    end
  end

  def finish_auth(agent, _domain, { challenge, response }) do
    uri = challenge["uri"]
    case send_request(agent, uri, resource: "challenge", keyAuthorization: response) do
      { :ok, %HTTPoison.Response{ status_code: 202 } } -> check_auth(uri)
      { _, resp } -> { :error, :unknown, inspect resp }
    end
  end

  def request_cert(agent, cert_opts) do
    [ first_domain | alternate_domains ] = cert_opts["names"]
    commands = "req -new -sha256 -outform der -key #{cert_opts["key"]} " <>
      "-subj \"/C=#{cert_opts["country"]}/ST=#{cert_opts["state"]}/O=#{cert_opts["organization"]}/CN=#{first_domain}\""
    { file_path, commands } = if List.first(alternate_domains) do
      ssl_config = File.read!(cert_opts["ssl_config"])
      domains = Enum.map(alternate_domains, fn(d) -> "DNS:#{d}" end) |> Enum.join(",")
      tmp_file = (cert_opts["temp_dir"] || "/tmp")
        |> generate_temp_file(ssl_config <> "\n[SAN]\nsubjectAltName=#{domains}")
      { tmp_file, commands <> " -reqexts SAN -config #{tmp_file_path}" }
    else
      { nil, commands <> " -config #{cert_opts["ssl_config"]}" }
    end
    %Porcelain.Result{ out: csr, status: 0 } = Porcelain.shell("openssl " <> commands)
    case resource_request(agent, "new-cert", csr: csr |> AcmeClient.le_b64 ) do
      { :ok, %HTTPoison.Response{ status_code: 201, body: cert } } ->
        
    end
    if file_path, do: :file.delete(file_path)
    { :ok }
  end

  defp check_auth(url, times \\ 0)
  defp check_auth(_url, 20), do: { :error, :timeout, "Still pending after 20 tries"}
  defp check_auth(uri, times) do
    case HTTPoison.get(uri) do
      { :ok, %HTTPoison.Response{ body: body } } ->
        result = JSON.decode!(body)
        case result["status"] do
          "valid" -> { :ok }
          "pending" ->
            IO.puts "Pending, rechecking in 5 seconds."
            :timer.sleep(5000)
            check_auth(uri, times + 1)
          _ ->
            { :error, :invalid, "Challenge attempt #{ result["status"] }: #{ result["error"]["details"] }" }
        end
      { _, resp } -> { :error, :unknown, inspect resp }
    end
  end

  # Worker helpers
  defp resource_request(agent, resource, payload) when is_list(payload) do
    path = get(agent, :endpoints)[resource]
    send_request(agent, path, [ { :resource, resource } | payload ])
  end

  defp send_request(agent, path, payload) do
    header = get(agent, :header)
    request = %{
      payload: AcmeClient.le_b64(payload),
      header: header,
      protected: Map.merge(header, %{ nonce: nonce(agent) }) |> AcmeClient.le_b64
    }
    signature = "#{request[:protected]}.#{request[:payload]}"
      |> :public_key.sign( :sha256, get(agent, :key) )
      |> AcmeClient.le_b64
    request = Map.put(request, :signature, signature) |> JSON.encode!()
    HTTPoison.post(path, request)
  end

  defp nonce(agent) do
    { :ok, %{ headers: le_headers } } = HTTPoison.head(get(agent, "api_location") <> "/directory")
    Enum.into(le_headers, %{})["Replay-Nonce"]
  end

  defp get(agent, key) do
    Agent.get(agent, &Map.get(&1, key))
  end

  defp random_string(len) do
    :crypto.strong_rand_bytes(len) |> Base.url_encode64 |> binary_part(0, len)
  end

  defp tmp_file_name(temp_dir, name \\ nil) do
    cond do
      !name -> ( Enum.random(15..45) |> random_string() )
      Path.join(temp_dir, name) |> File.exists? -> tmp_file_name(temp_dir, nil)
      true -> Path.join(temp_dir, name)
    end
  end

  defp generate_temp_file(temp_dir, contents) do
    path = tmp_file_name(temp_dir)
    File.write!(path, contents)
    path
  end

end
