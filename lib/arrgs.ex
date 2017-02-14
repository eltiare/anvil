defmodule Arrgs do

  import OptionParser

  def verbose_parse(args, opts \\ []) do
    mapOpts = Enum.into(opts, %{})
    { switches, methods, unknown } = parse(args, opts)
    cond do
      mapOpts[:strict] && !List.first(mapOpts[:strict]) && List.first(switches) ->
        NginxDockerCerts.err "Invalid options:\n#{inspect switches}"
      mapOpts[:strict] && List.first(unknown) ->
        NginxDockerCerts.err "Invalid options:\n#{inspect unknown}"
      true ->
        { switches, methods, unknown }
    end
  end

  def revert(list) when is_list(list) do
    Enum.map(list, fn(item) ->
      cond do
        is_tuple(item) ->
          if !elem(item, 1), do: elem(item, 0), else: "#{elem(item, 0)}=#{elem(item, 1)}"
        is_binary(item) -> item
      end
    end)
  end




end
