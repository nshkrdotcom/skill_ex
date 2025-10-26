#!/usr/bin/env elixir
# SPDX-License-Identifier: MIT

Mix.install([
  {:jason, "~> 1.4"}
])

script_dir = __DIR__

Code.require_file(Path.expand("../lib/skill_ex/manifest.ex", script_dir))
Code.require_file(Path.expand("../lib/skill_ex/aggregator.ex", script_dir))

defmodule SkillEx.Sync.CLI do
  @moduledoc false

  @switches [
    manifest: :string,
    target: :string,
    package_script: :string,
    dry_run: :boolean,
    clock: :string,
    version: :string
  ]

  def main(argv) do
    {opts, _argv} = OptionParser.parse!(argv, strict: @switches)

    manifest_path =
      opts
      |> Keyword.get(:manifest)
      |> required!("--manifest")
      |> Path.expand()

    target_root =
      opts
      |> Keyword.get(:target, Path.join(File.cwd!(), "skills"))
      |> Path.expand()

    manifest = SkillEx.Manifest.load!(manifest_path)
    repos = Map.get(manifest, "repositories", [])

    clock_fn = build_clock(opts[:clock])

    package_cmd =
      case opts[:package_script] do
        nil -> nil
        script -> [Path.expand(script)]
      end

    sync_opts = [
      manifest: manifest_path,
      dry_run: Keyword.get(opts, :dry_run, false),
      package_cmd: package_cmd,
      clock: clock_fn
    ]

    result = SkillEx.Aggregator.sync_repos(repos, target_root, sync_opts)

    {status, summary, exit_code} =
      case result do
        {:ok, summary} -> {"ok", summary, 0}
        {:error, summary} -> {"error", summary, 1}
      end

    payload =
      %{
        "status" => status,
        "summary" => stringify(summary),
        "target" => target_root
      }
      |> maybe_put("version", opts[:version])

    IO.puts(Jason.encode!(payload, pretty: true))
    System.halt(exit_code)
  end

  defp required!(nil, flag), do: raise(ArgumentError, "missing required flag #{flag}")
  defp required!(value, _flag), do: value

  defp build_clock(nil), do: fn -> DateTime.utc_now() end

  defp build_clock(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, datetime, _offset} -> fn -> datetime end
      {:error, reason} -> raise ArgumentError, "invalid --clock value: #{inspect(reason)}"
    end
  end

  defp stringify(value) when is_map(value) do
    value
    |> Enum.map(fn {key, val} -> {to_string(key), stringify(val)} end)
    |> Enum.into(%{})
  end

  defp stringify(value) when is_list(value) do
    Enum.map(value, &stringify/1)
  end

  defp stringify(value), do: value

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

SkillEx.Sync.CLI.main(System.argv())
