defmodule SkillEx.TestHelpers do
  @moduledoc false

  @skill_frontmatter """
  ---
  name: sample-skill
  description: Sample skill for testing.
  license: MIT
  ---

  # Sample Skill

  Placeholder content for automated tests.
  """

  def unique_tmp_dir!(context) do
    base = Path.join(System.tmp_dir!(), "skill_ex-tests")
    suffix = "#{context.module}-#{context.test}-#{System.unique_integer([:positive])}"
    path = Path.join(base, suffix)
    File.rm_rf!(path)
    mkdir_p!(path)
    path
  end

  def write_manifest!(path, manifest_map) when is_map(manifest_map) do
    mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(manifest_map, pretty: true))
    path
  end

  def empty_manifest(repos \\ []) do
    %{
      "version" => 1,
      "generated_at" => nil,
      "repositories" => Enum.map(repos, &stringify_keys/1),
      "skills" => []
    }
  end

  def stringify_keys(map) do
    for {k, v} <- map, into: %{} do
      {to_string(k), v}
    end
  end

  def create_repo_with_skill!(root, repo_name, skill_name \\ "sample-skill") do
    repo_dir = Path.join(root, repo_name)
    skill_dir = Path.join(repo_dir, ".claude/skills/#{skill_name}")
    mkdir_p!(skill_dir)
    File.write!(Path.join(skill_dir, "SKILL.md"), @skill_frontmatter)

    references_dir = Path.join(skill_dir, "references")
    mkdir_p!(references_dir)
    File.write!(Path.join(references_dir, "README.md"), "# References\n")

    repo_dir
  end

  def stub_package_script!(root, name, exit_code \\ 0, opts \\ []) do
    script_path = Path.join(root, "#{name}.sh")

    body =
      case Keyword.get(opts, :mode, :success) do
        :success ->
          """
          #!/usr/bin/env bash
          echo "{\\"status\\":\\"ok\\",\\"skill\\":\\"$1\\"}"
          exit #{exit_code}
          """

        :failure ->
          """
          #!/usr/bin/env bash
          echo "{\\"status\\":\\"error\\",\\"skill\\":\\"$1\\"}" >&2
          exit #{exit_code}
          """
      end

    File.write!(script_path, body)
    File.chmod!(script_path, 0o755)
    script_path
  end

  def read_manifest!(path) do
    path |> File.read!() |> Jason.decode!()
  end

  def zip_entries(zip_path) do
    {:ok, entries} = :zip.table(String.to_charlist(zip_path))

    entries
    |> Enum.flat_map(fn
      {:zip_comment, _comment} ->
        []

      {:zip_file, entry_name, _info, _comment, _offset, _size} ->
        [List.to_string(entry_name)]

      {:zip_file, entry_name, _info, _comment, _offset, _csize, _uncsize} ->
        [List.to_string(entry_name)]

      {entry_name, _, _, _, _, _, _} ->
        [List.to_string(entry_name)]

      _ ->
        []
    end)
  end

  defp mkdir_p!(path) do
    case File.mkdir_p(path) do
      :ok -> :ok
      {:error, reason} -> raise File.Error, reason: reason, action: "make directory", path: path
    end
  end
end
