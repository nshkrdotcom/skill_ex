defmodule SkillEx.Aggregator do
  @moduledoc """
  Coordinates collecting `.claude/skills` directories from multiple Elixir projects.
  """

  alias SkillEx.Manifest

  @default_skills_dir ".claude/skills"

  @typedoc "Map describing a repository that exports skills."
  @type repo_config :: %{
          required(:name) => String.t(),
          required(:path) => String.t(),
          optional(:skills_dir) => String.t()
        }

  @typedoc "Summary map returned after syncing repositories."
  @type sync_summary :: %{
          required(:planned) => non_neg_integer(),
          required(:copied) => non_neg_integer(),
          required(:validated) => non_neg_integer(),
          required(:errors) => [term()],
          required(:timestamp) => String.t()
        }

  @doc """
  Synchronise the aggregator skills directory with the configured repositories.
  """
  @spec sync_repos([repo_config()], Path.t(), keyword()) ::
          {:ok, sync_summary()} | {:error, sync_summary()}
  def sync_repos(repos, target_root, opts \\ []) when is_list(repos) do
    with :ok <- ensure_directory(target_root) do
      timestamp = Keyword.get(opts, :clock, &DateTime.utc_now/0).()
      dry_run = Keyword.get(opts, :dry_run, false)
      manifest_path = Keyword.get(opts, :manifest)
      package_cmd = Keyword.get(opts, :package_cmd)
      package_env = Keyword.get(opts, :package_env, %{})
      package_cwd = Keyword.get(opts, :package_cwd)

      default_validator = fn path ->
        validate_skill(path,
          package_cmd: package_cmd,
          env: package_env,
          package_cwd: package_cwd
        )
      end

      validator = Keyword.get(opts, :validator, default_validator)

      initial_summary = %{planned: 0, copied: 0, validated: 0, errors: []}

      {summary, successes} =
        repos
        |> Enum.map(&normalize_repo/1)
        |> Enum.reduce({initial_summary, []}, fn repo, acc ->
          reduce_repo(repo, target_root, validator, dry_run, timestamp, acc)
        end)

      summary =
        summary
        |> Map.update!(:errors, &Enum.reverse/1)
        |> Map.put(:timestamp, DateTime.to_iso8601(timestamp))

      maybe_update_manifest(manifest_path, successes, timestamp, dry_run)

      case summary.errors do
        [] -> {:ok, summary}
        _ -> {:error, summary}
      end
    else
      {:error, reason} ->
        summary = %{
          planned: 0,
          copied: 0,
          validated: 0,
          errors: [%{reason: reason}],
          timestamp: DateTime.to_iso8601(DateTime.utc_now())
        }

        {:error, summary}
    end
  end

  @doc """
  Validate a single skill directory using the shared packaging script.
  """
  @spec validate_skill(Path.t(), keyword()) :: :ok | {:error, term()}
  def validate_skill(skill_path, opts \\ []) do
    case normalize_cmd(Keyword.get(opts, :package_cmd)) do
      nil ->
        :ok

      {command, args} ->
        env =
          opts
          |> Keyword.get(:env, %{})
          |> Enum.map(fn {key, value} -> {to_string(key), to_string(value)} end)

        cmd_opts =
          [
            stderr_to_stdout: true,
            env: env
          ]
          |> maybe_put(:cd, Keyword.get(opts, :package_cwd))

        try do
          {output, status} = System.cmd(command, args ++ [skill_path], cmd_opts)

          if status == 0 do
            :ok
          else
            {:error,
             %{
               reason: :validation_failed,
               status: status,
               output: output,
               path: skill_path
             }}
          end
        rescue
          error ->
            {:error,
             %{
               reason: :command_error,
               error: Exception.message(error),
               path: skill_path
             }}
        end
    end
  end

  @doc """
  Produce a consolidated zip archive for all synced skills.
  """
  @spec package_all(Path.t(), keyword()) :: {:ok, Path.t()} | {:error, term()}
  def package_all(skills_root, opts \\ []) do
    dist_root = Keyword.get(opts, :dist, Path.join(skills_root, ".."))

    with :ok <- ensure_directory(dist_root),
         true <- File.dir?(skills_root) do
      files = collect_files(skills_root)

      if files == [] do
        {:error, %{reason: :nothing_to_package}}
      else
        version = Keyword.get(opts, :version, Date.utc_today() |> Date.to_iso8601())
        archive_name = "skills-pack-#{version}.zip"
        archive_path = Path.join(dist_root, archive_name)
        File.rm(archive_path)

        entries =
          Enum.map(files, fn file ->
            Path.relative_to(file, skills_root) |> String.to_charlist()
          end)

        case :zip.create(
               String.to_charlist(archive_path),
               entries,
               cwd: String.to_charlist(skills_root)
             ) do
          {:ok, _} ->
            {:ok, archive_path}

          {:error, reason} ->
            {:error, %{reason: reason}}
        end
      end
    else
      false ->
        {:error, %{reason: :skills_root_missing}}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  defp reduce_repo(repo, target_root, validator, dry_run, timestamp, {summary, successes}) do
    cond do
      !File.dir?(repo.path) ->
        {add_error(summary, %{repo: repo.name, reason: :missing_repo}), successes}

      true ->
        skills_root = Path.join(repo.path, repo.skills_dir)

        if File.dir?(skills_root) do
          case File.ls(skills_root) do
            {:ok, entries} ->
              Enum.reduce(entries, {summary, successes}, fn entry, acc ->
                source = Path.join(skills_root, entry)

                if File.dir?(source) do
                  process_skill(
                    repo,
                    entry,
                    source,
                    target_root,
                    validator,
                    dry_run,
                    timestamp,
                    acc
                  )
                else
                  acc
                end
              end)

            {:error, reason} ->
              {add_error(summary, %{repo: repo.name, reason: reason}), successes}
          end
        else
          {add_error(summary, %{repo: repo.name, reason: :missing_skills_dir}), successes}
        end
    end
  end

  defp process_skill(
         repo,
         skill_name,
         source_path,
         target_root,
         validator,
         dry_run,
         timestamp,
         {summary, successes}
       ) do
    summary = increment(summary, :planned)

    if dry_run do
      {summary, successes}
    else
      target_path = Path.join([target_root, repo.name, skill_name])
      ensure_directory(Path.dirname(target_path))
      File.rm_rf(target_path)

      case File.cp_r(source_path, target_path) do
        {:ok, _copied} ->
          summary = increment(summary, :copied)

          case validator.(target_path) do
            :ok ->
              metadata = build_skill_metadata(repo.name, skill_name, target_path, timestamp)
              summary = increment(summary, :validated)
              {summary, [metadata | successes]}

            {:error, reason} ->
              {add_error(summary, error_payload(repo.name, skill_name, reason)), successes}
          end

        {:error, reason, file} ->
          {add_error(summary, %{repo: repo.name, skill: skill_name, reason: reason, file: file}),
           successes}
      end
    end
  end

  defp ensure_directory(path) do
    case File.mkdir_p(path) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp collect_files(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
  end

  defp normalize_repo(repo) do
    name =
      repo
      |> get_value(:name)
      |> to_string()

    path =
      repo
      |> get_value(:path)
      |> Path.expand()

    skills_dir =
      repo
      |> Map.get(:skills_dir) ||
        Map.get(repo, "skills_dir") ||
        @default_skills_dir

    %{name: name, path: path, skills_dir: skills_dir}
  end

  defp get_value(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp increment(summary, key) do
    Map.update!(summary, key, &(&1 + 1))
  end

  defp add_error(summary, error) do
    Map.update!(summary, :errors, fn errors -> [error | errors] end)
  end

  defp build_skill_metadata(repo_name, skill_name, target_path, timestamp) do
    %{
      repo: repo_name,
      name: skill_name,
      target_path: Path.join(repo_name, skill_name),
      checksum: checksum_for_dir(target_path),
      packaged_at: DateTime.to_iso8601(timestamp)
    }
  end

  defp checksum_for_dir(root) do
    files =
      root
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&File.regular?/1)
      |> Enum.sort()

    files
    |> Enum.reduce(:crypto.hash_init(:sha256), fn file, acc ->
      relative = Path.relative_to(file, root)
      contents = File.read!(file)

      acc
      |> :crypto.hash_update(relative)
      |> :crypto.hash_update(contents)
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp error_payload(repo_name, skill_name, reason) when is_map(reason) do
    reason
    |> Map.put_new(:reason, Map.get(reason, :reason, :validation_error))
    |> Map.put(:repo, repo_name)
    |> Map.put(:skill, skill_name)
  end

  defp error_payload(repo_name, skill_name, reason) do
    %{repo: repo_name, skill: skill_name, reason: reason}
  end

  defp maybe_update_manifest(nil, _successes, _timestamp, _dry_run), do: :ok
  defp maybe_update_manifest(_path, _successes, _timestamp, true), do: :ok

  defp maybe_update_manifest(path, successes, timestamp, false) do
    if successes == [] do
      :ok
    else
      manifest =
        path
        |> Manifest.load!()
        |> Manifest.touch_generated_at(timestamp)

      updated =
        Enum.reduce(successes, manifest, fn entry, acc ->
          Manifest.put_skill(acc, %{
            "name" => entry.name,
            "source_repo" => entry.repo,
            "checksum" => entry.checksum,
            "packaged_at" => entry.packaged_at,
            "target_path" => entry.target_path
          })
        end)

      Manifest.save!(path, updated)
    end
  end

  defp normalize_cmd(nil), do: nil
  defp normalize_cmd([]), do: nil

  defp normalize_cmd(cmd) when is_binary(cmd) do
    {cmd, []}
  end

  defp normalize_cmd([command | rest]) do
    {command, rest}
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
