defmodule NginxDockerCerts do

  def main(args) do
    allowed_switches = [
      k: :string, rsa_key: :string,
      host: :string, h: :string,
      prod: :boolean, p: :boolean
    ]
    aliases = [ k: :rsa_key, s: :staging, h: :host, p: :prod ]
    { switches, commands, unknown } = Arrgs.verbose_parse(args, switches: allowed_switches, aliases: aliases)
    { command, newCommands } = List.pop_at(commands, 0, nil)
    newSwitches = Arrgs.revert(unknown)
    call_func = case command do
      "register" -> &(register/2)
      "authorize-domains" -> &(authorize_domains/2)
      "test" -> &(test/2)
      _ -> err "Invalid command: #{command}"
    end
    get_config(switches)
    call_func.(newCommands, newSwitches)
  end

  defp register(commands, switches) do
    command = List.first(commands)

    unless command && String.match?(command, ~r/^\s*.+@.+(\s*,\s*.+@.+)*\s*$/) && length(commands) == 1 do
      err "Please pass a list of valid email addresses seperated by commas to `register`\nThis is the only argument."
    end
    Arrgs.verbose_parse(switches, strict: []) # Safegaurd against errant options passed

    contacts = String.split(command, ",")
      |> Enum.map( fn(str) -> "mailto:" <> String.trim(str) end )

    case resource_request("new-reg", contact: contacts ) do

      { :ok, %HTTPoison.Response{ status_code: 201, headers: headers }} ->
        location = Enum.into(headers, %{})["Location"]
        tos_link = Utils.valuesFor(headers, "Link")
          |> Enum.find(fn(str) -> String.match?(str, ~r/terms-of-service/) end)
          |> String.replace(~r/.*<([^>]+)>.*/, "\\1")
        IO.puts "Accepting the terms and services available at #{tos_link}..."
        case send_request(location, resource: "reg", agreement: tos_link) do

          { :ok, %HTTPoison.Response{ status_code: 202 } } ->
            IO.puts "\nRegistration is successful and the TOS have been accepted."

          { _, response } ->
            IO.puts "\nRegistration is successful but there was a problem with the TOS:\n\n#{inspect response}"
        end

      { _, response } ->
        err "\nThere was an error processing the request:\n\n#{ inspect response }\n"
    end

  end

  defp authorize_domains(commands, switches) do
    domains = List.first(commands) |> String.split(",")
    { switches, _, _ } = Arrgs.verbose_parse(switches, strict: [ web_root: :string, wait: :boolean ])
    { :ok, pid } = AuthRequests.start_link
    AuthRequests.get_auths(pid, domains, switches[:web_root] || "html" )
    File.gets "Files have been written. Press enter to continue."
  end

  defp complete_authorize(path) do
    IO.puts "Checking #{path}..."
    case HTTPoison.get(path) do
      { :ok, %HTTPoison.Response{ body: body } } ->
        result = JSON.decode!(body)
        case result["status"] do
          "valid" ->
            IO.puts "Authorization accepted."
            true
          "pending" ->
            IO.puts "Authorization pending. Rechecking in 15 seconds..."
            :timer.sleep(15000)
            complete_authorize(path)
          _ ->
            err "Challenge attempt #{ result["status"] }: #{ result["error"]["details"] }"
        end
      { _, resp } -> err(inspect resp)
    end
  end

  defp test(_commands, _switches) do
    { :ok, pid } = AuthRequests.start_link
    AuthRequests.start_auths(pid, ["accentuate.me", "smashingshots.com", "git.accentuate.me"])
  end

  defp get_config(switches) do
    switches = Enum.into(switches, %{})
    Config.start_link
    [private_pem] = File.read!(switches[:rsa_key] || "acme_key/private.key")
      |> :public_key.pem_decode
    host = cond do
      switches[:prod] -> "https://acme-v01.api.letsencrypt.org/"
      switches[:host] -> switches[:host]
      true -> "https://acme-staging.api.letsencrypt.org"
    end
    { :ok, %{ body: body } } = HTTPoison.get( host <> "/directory" )
    Config.merge(%{
        key: :public_key.pem_entry_decode(private_pem),
        host: host,
        endpoints: JSON.decode!(body)
      })
    { :ok }
  end

  def resource_request(resource, payload) when is_list(payload) do
    path = Config.get(:endpoints)[resource]
    send_request(path, payload ++ [ resource: resource] )
  end

  def send_request(path, payload) do
    header = get_header()
    request = %{
      payload: Utils.le_b64(payload),
      header: header,
      protected: Map.merge(header, %{ nonce: nonce() }) |> Utils.le_b64
    }
    signature = "#{request[:protected]}.#{request[:payload]}"
      |> :public_key.sign( :sha256, Config.get(:key) )
      |> Utils.le_b64
    request = Map.put(request, :signature, signature)
    HTTPoison.post(path, JSON.encode!(request))
  end

  defp nonce() do
    { :ok, %{ headers: le_headers } } = HTTPoison.head(Config.get(:host) <> "/directory")
    Enum.into(le_headers, %{})["Replay-Nonce"]
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
  defp get_header() do
    if header = Config.get(:header) do
      header
    else
      tuple = Config.get(:key)
      # TODO: figure out a way to calculate the sizes, don't hardcode
      modulus = <<elem(tuple, 2)::2048>> |> Utils.le_b64
      exponent = <<elem(tuple, 3)::24>> |> Utils.le_b64
      header = %{
        alg: "RS256",
        jwk: [ e: exponent, kty: "RSA", n: modulus ]
      }
      Config.put(:header, header)
      header
    end
  end

  def get_thumbprint() do
    if thumbprint = Config.get(:thumprint) do
      thumbprint
    else
      jwk = get_header()[:jwk] |> JSON.encode!
      IO.puts jwk
      thumbprint = :crypto.hash(:sha256, jwk) |> Utils.le_b64
      Config.put(:thumbprint, thumbprint)
      thumbprint
    end
  end

  def err(msg) do
    IO.puts msg
    Process.exit self(), :error
  end

end
