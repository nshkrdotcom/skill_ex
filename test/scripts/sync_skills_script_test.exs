defmodule SkillEx.SyncSkillsScriptTest do
  use ExUnit.Case, async: false

  alias SkillEx.TestHelpers

  @script_path Path.expand("../../scripts/sync_skills.exs", __DIR__)
  @project_root Path.expand("../..", __DIR__)

  setup context do
    tmp = TestHelpers.unique_tmp_dir!(context)
    on_exit(fn -> File.rm_rf!(tmp) end)

    repos_root = Path.join(tmp, "repos")
    File.mkdir_p!(repos_root)

    skills_root = Path.join(tmp, "skills")
    File.mkdir_p!(skills_root)

    manifest_path = Path.join(tmp, "manifest.json")

    %{tmp: tmp, repos_root: repos_root, skills_root: skills_root, manifest_path: manifest_path}
  end

  test "sync script copies skills and emits a JSON summary",
       %{repos_root: repos_root, skills_root: skills_root, manifest_path: manifest_path, tmp: tmp} do
    repo = TestHelpers.create_repo_with_skill!(repos_root, "script_repo", "script-skill")
    repos = [%{name: "script_repo", path: repo, skills_dir: ".claude/skills"}]

    manifest = TestHelpers.empty_manifest(repos)
    TestHelpers.write_manifest!(manifest_path, manifest)

    package_script = TestHelpers.stub_package_script!(tmp, "package", 0, mode: :success)

    {output, exit_status} =
      System.cmd(
        "elixir",
        [
          @script_path,
          "--manifest",
          manifest_path,
          "--target",
          skills_root,
          "--package-script",
          package_script,
          "--clock",
          "2025-10-08T12:00:00Z"
        ],
        cd: @project_root,
        stderr_to_stdout: true
      )

    assert exit_status == 0
    assert {:ok, result} = Jason.decode(output)
    assert result["status"] == "ok"
    assert result["summary"]["copied"] == 1

    assert File.exists?(Path.join([skills_root, "script_repo", "script-skill", "SKILL.md"]))
  end

  test "sync script honors --dry-run",
       %{repos_root: repos_root, skills_root: skills_root, manifest_path: manifest_path, tmp: tmp} do
    repo = TestHelpers.create_repo_with_skill!(repos_root, "dry_script_repo", "dry-script")
    repos = [%{name: "dry_script_repo", path: repo, skills_dir: ".claude/skills"}]

    manifest = TestHelpers.empty_manifest(repos)
    TestHelpers.write_manifest!(manifest_path, manifest)

    package_script = TestHelpers.stub_package_script!(tmp, "package", 0, mode: :success)

    {output, exit_status} =
      System.cmd(
        "elixir",
        [
          @script_path,
          "--manifest",
          manifest_path,
          "--target",
          skills_root,
          "--package-script",
          package_script,
          "--dry-run"
        ],
        cd: @project_root,
        stderr_to_stdout: true
      )

    assert exit_status == 0
    assert {:ok, result} = Jason.decode(output)
    assert result["summary"]["copied"] == 0
    refute File.exists?(Path.join([skills_root, "dry_script_repo", "dry-script"]))
  end
end
