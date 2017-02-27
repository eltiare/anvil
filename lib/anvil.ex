defmodule Anvil do

  def main(args) do
    allowed_switches = [ config: :string, c: :string ]
    aliases = [ c: :config ]
    { switches, commands, u } = OptionParser.parse(args,
                                            strict: allowed_switches,
                                            aliases: aliases)
     cond do
       List.first(u) ->
         IO.puts "Only option is -c or --config"
         Process.exit(self(), :error)
       switches[:config] -> switches[:config]
       true -> "anvil-options.yml"
     end |> load_config
     { command, _ } = List.pop_at(commands, 0, nil)
     call_function = case command do
       "register" -> &(register/1)
       "server" -> &(server/1)
       "test" -> &(test/1)
       _ -> err "Invalid command: #{command}"
     end
     { :ok, acme } = Config.get() |> AcmeClient.start_link()
     call_function.(acme)
  end

  defp load_config(yaml) do
    YamlElixir.read_from_file(yaml) |> Config.start_link
    host = Config.get_or_put("api_location", "https://acme-v01.api.letsencrypt.org/")
    app_key = Config.get("app_key") || throw({:config_error, msg: "app_key is required"})
    { :ok, %{ body: body } } = HTTPoison.get( host <> "/directory" )
    Config.merge(%{
        key: File.read!(app_key) |> AcmeClient.decode_key(),
        host: host,
        endpoints: JSON.decode!(body)
      })
  end

  defp register(acme) do
    AcmeClient.register(acme, Config.get("contacts"))
  end

  defp server(acme) do
    certs = Config.get("certificates")
    for cert <- certs do
      # IO.inspect AcmeClient.authorize_domains(acme, cert["names"])
      AcmeClient.request_certificate(acme, cert)
    end
  end

  defp test(_) do

  end

  defp err(msg) do
    IO.puts msg
    self() |> Process.exit(:error)
  end

end
