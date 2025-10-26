defmodule SkillEx.AggregatorTest do
  use ExUnit.Case, async: true

  alias SkillEx.Aggregator
  alias SkillEx.TestHelpers

  setup context do
    tmp = TestHelpers.unique_tmp_dir!(context)
    on_exit(fn -> File.rm_rf!(tmp) end)

    skills_root = Path.join(tmp, "skills")
    File.mkdir_p!(skills_root)

    manifest_path = Path.join(tmp, "manifest.json")

    %{tmp: tmp, skills_root: skills_root, manifest_path: manifest_path}
  end

  describe "sync_repos/3" do
    test "copies skills, validates them, and updates the manifest",
         %{tmp: tmp, skills_root: skills_root, manifest_path: manifest_path} do
      repos_root = Path.join(tmp, "repos")
      File.mkdir_p!(repos_root)

      alpha_repo = TestHelpers.create_repo_with_skill!(repos_root, "alpha_repo", "alpha-skill")
      beta_repo = TestHelpers.create_repo_with_skill!(repos_root, "beta_repo", "beta-skill")

      repos = [
        %{name: "alpha_repo", path: alpha_repo, skills_dir: ".claude/skills"},
        %{name: "beta_repo", path: beta_repo, skills_dir: ".claude/skills"}
      ]

      manifest = TestHelpers.empty_manifest(repos)
      TestHelpers.write_manifest!(manifest_path, manifest)

      parent = self()

      validator =
        fn target_skill_path ->
          send(parent, {:validated, Path.relative_to_cwd(target_skill_path)})
          :ok
        end

      frozen_clock = fn -> ~U[2025-10-08 12:00:00Z] end

      assert {:ok, summary} =
               Aggregator.sync_repos(
                 repos,
                 skills_root,
                 manifest: manifest_path,
                 validator: validator,
                 clock: frozen_clock
               )

      assert summary.copied == 2
      assert summary.validated == 2
      assert summary.errors == []

      assert_receive {:validated, _}
      assert_receive {:validated, _}

      alpha_target = Path.join([skills_root, "alpha_repo", "alpha-skill", "SKILL.md"])
      beta_target = Path.join([skills_root, "beta_repo", "beta-skill", "SKILL.md"])

      assert File.exists?(alpha_target)
      assert File.exists?(beta_target)

      manifest_after = TestHelpers.read_manifest!(manifest_path)
      assert manifest_after["generated_at"] == "2025-10-08T12:00:00Z"
      assert Enum.count(manifest_after["skills"]) == 2

      assert Enum.any?(manifest_after["skills"], fn skill ->
               skill["name"] == "alpha-skill" &&
                 skill["source_repo"] == "alpha_repo" &&
                 String.length(skill["checksum"]) == 64
             end)
    end

    test "supports dry-run mode without touching files or manifest",
         %{tmp: tmp, skills_root: skills_root, manifest_path: manifest_path} do
      repos_root = Path.join(tmp, "repos")
      File.mkdir_p!(repos_root)

      repo = TestHelpers.create_repo_with_skill!(repos_root, "dry_run_repo", "dry-skill")
      repos = [%{name: "dry_run_repo", path: repo, skills_dir: ".claude/skills"}]

      manifest = TestHelpers.empty_manifest(repos)
      TestHelpers.write_manifest!(manifest_path, manifest)

      assert {:ok, summary} =
               Aggregator.sync_repos(
                 repos,
                 skills_root,
                 manifest: manifest_path,
                 dry_run: true
               )

      assert summary.copied == 0
      assert summary.validated == 0
      assert summary.planned == 1
      assert summary.errors == []

      refute File.exists?(Path.join([skills_root, "dry_run_repo", "dry-skill"]))
      manifest_after = TestHelpers.read_manifest!(manifest_path)
      assert manifest_after["skills"] == []
    end

    test "collects errors when repositories are missing",
         %{skills_root: skills_root, manifest_path: manifest_path} do
      repos = [
        %{
          name: "ghost_repo",
          path: "/tmp/ghost_repo_#{System.unique_integer()}",
          skills_dir: ".claude/skills"
        }
      ]

      manifest = TestHelpers.empty_manifest(repos)
      TestHelpers.write_manifest!(manifest_path, manifest)

      assert {:error, summary} =
               Aggregator.sync_repos(
                 repos,
                 skills_root,
                 manifest: manifest_path
               )

      assert summary.copied == 0
      assert summary.validated == 0
      assert summary.errors != []
      assert hd(summary.errors)[:repo] == "ghost_repo"
    end
  end

  describe "validate_skill/2" do
    test "returns :ok when the packaging script succeeds", %{tmp: tmp} do
      scripts_root = Path.join(tmp, "scripts")
      File.mkdir_p!(scripts_root)

      script = TestHelpers.stub_package_script!(scripts_root, "package", 0, mode: :success)
      skill_dir = Path.join(tmp, "skills/sample")
      File.mkdir_p!(skill_dir)

      assert :ok =
               Aggregator.validate_skill(skill_dir,
                 package_cmd: [script],
                 env: %{"SKILL_PATH" => skill_dir}
               )
    end

    test "returns an error tuple when the packaging script fails", %{tmp: tmp} do
      scripts_root = Path.join(tmp, "scripts")
      File.mkdir_p!(scripts_root)

      script = TestHelpers.stub_package_script!(scripts_root, "package_fail", 1, mode: :failure)
      skill_dir = Path.join(tmp, "skills/sample")
      File.mkdir_p!(skill_dir)

      assert {:error, %{status: 1}} =
               Aggregator.validate_skill(skill_dir,
                 package_cmd: [script],
                 env: %{"SKILL_PATH" => skill_dir}
               )
    end
  end

  describe "package_all/2" do
    test "creates a skills-pack archive containing every skill directory",
         %{tmp: tmp, skills_root: skills_root} do
      dist_root = Path.join(tmp, "dist")
      File.mkdir_p!(dist_root)

      File.mkdir_p!(Path.join([skills_root, "alpha_repo", "alpha-skill"]))
      File.write!(Path.join([skills_root, "alpha_repo", "alpha-skill", "SKILL.md"]), "# alpha\n")

      File.mkdir_p!(Path.join([skills_root, "beta_repo", "beta-skill"]))
      File.write!(Path.join([skills_root, "beta_repo", "beta-skill", "SKILL.md"]), "# beta\n")

      assert {:ok, archive_path} =
               Aggregator.package_all(
                 skills_root,
                 dist: dist_root,
                 version: "2025.10.08"
               )

      assert File.exists?(archive_path)
      assert archive_path =~ "skills-pack-2025.10.08.zip"

      entries = TestHelpers.zip_entries(archive_path)

      assert Enum.any?(entries, &String.contains?(&1, "alpha_repo/alpha-skill/SKILL.md"))
      assert Enum.any?(entries, &String.contains?(&1, "beta_repo/beta-skill/SKILL.md"))
    end

    test "returns an error when no skills are present", %{tmp: tmp} do
      skills_root = Path.join(tmp, "empty-skills")
      File.mkdir_p!(skills_root)

      assert {:error, %{reason: :nothing_to_package}} =
               Aggregator.package_all(skills_root, dist: Path.join(tmp, "dist"))
    end
  end
end
