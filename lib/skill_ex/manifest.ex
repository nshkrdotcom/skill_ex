defmodule SkillEx.Manifest do
  @moduledoc """
  Manifest utilities for the skill aggregator.

  Functions here are purposely left unimplemented so the failing tests define
  the behaviour we need to build.
  """

  @type manifest :: map()

  @default_manifest %{
    "version" => 1,
    "generated_at" => nil,
    "repositories" => [],
    "skills" => []
  }

  @doc """
  Load and decode the manifest JSON file from disk.
  """
  @spec load!(Path.t()) :: manifest()
  def load!(path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> Jason.decode!()
      |> ensure_defaults()
    else
      @default_manifest
    end
  end

  @doc """
  Save the manifest map back to disk as JSON.
  """
  @spec save!(Path.t(), manifest()) :: :ok
  def save!(path, manifest) when is_map(manifest) do
    ensure_directory!(Path.dirname(path))
    File.write!(path, Jason.encode!(ensure_defaults(manifest), pretty: true))
    :ok
  end

  @doc """
  Insert or replace a skill entry.
  """
  @spec put_skill(manifest(), map()) :: manifest()
  def put_skill(manifest, skill_map) when is_map(manifest) and is_map(skill_map) do
    skill = stringify_keys(skill_map)

    skills =
      manifest
      |> Map.get("skills", [])
      |> Enum.reject(fn existing ->
        existing["name"] == skill["name"] and existing["source_repo"] == skill["source_repo"]
      end)
      |> Kernel.++([skill])

    Map.put(manifest, "skills", skills)
  end

  @doc """
  Update the generated_at timestamp.
  """
  @spec touch_generated_at(manifest(), DateTime.t()) :: manifest()
  def touch_generated_at(manifest, %DateTime{} = datetime) do
    Map.put(manifest, "generated_at", DateTime.to_iso8601(datetime))
  end

  defp ensure_directory!(path) do
    case File.mkdir_p(path) do
      :ok -> :ok
      {:error, reason} -> raise File.Error, reason: reason, action: "create directory", path: path
    end
  end

  defp ensure_defaults(manifest) do
    manifest
    |> Map.put_new("version", 1)
    |> Map.put_new("generated_at", nil)
    |> Map.put_new("repositories", [])
    |> Map.put_new("skills", [])
  end

  defp stringify_keys(map) do
    for {key, value} <- map, into: %{} do
      {to_string(key), value}
    end
  end
end
