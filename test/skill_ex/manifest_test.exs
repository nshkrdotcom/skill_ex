defmodule SkillEx.ManifestTest do
  use ExUnit.Case, async: true

  alias SkillEx.Manifest
  alias SkillEx.TestHelpers

  setup context do
    tmp = TestHelpers.unique_tmp_dir!(context)
    on_exit(fn -> File.rm_rf!(tmp) end)

    manifest_path = Path.join(tmp, "manifest.json")
    %{tmp: tmp, manifest_path: manifest_path}
  end

  test "load!/1 parses the manifest JSON into a map with string keys",
       %{manifest_path: manifest_path} do
    repos = [
      %{name: "alpha_repo", path: "../alpha", skills_dir: ".claude/skills"}
    ]

    manifest = TestHelpers.empty_manifest(repos)
    TestHelpers.write_manifest!(manifest_path, manifest)

    loaded = Manifest.load!(manifest_path)

    assert is_map(loaded)
    assert Map.has_key?(loaded, "repositories")
    assert [%{"name" => "alpha_repo"}] = loaded["repositories"]
  end

  test "save!/2 persists the manifest back to disk as JSON",
       %{manifest_path: manifest_path} do
    manifest = TestHelpers.empty_manifest()
    Manifest.save!(manifest_path, manifest)

    assert File.exists?(manifest_path)
    assert {:ok, decoded} = File.read(manifest_path)
    assert String.contains?(decoded, "\"version\"")
  end

  test "put_skill/2 inserts or replaces a skill entry" do
    manifest = TestHelpers.empty_manifest()

    updated =
      manifest
      |> Manifest.put_skill(%{
        "name" => "alpha-skill",
        "source_repo" => "alpha_repo",
        "checksum" => "aaa",
        "packaged_at" => "2025-10-08T12:00:00Z"
      })
      |> Manifest.put_skill(%{
        "name" => "alpha-skill",
        "source_repo" => "alpha_repo",
        "checksum" => "bbb",
        "packaged_at" => "2025-10-08T12:00:01Z"
      })

    assert [%{"checksum" => "bbb"}] = updated["skills"]
  end

  test "touch_generated_at/2 stamps the manifest with the given datetime" do
    manifest = TestHelpers.empty_manifest()
    timestamp = ~U[2025-10-08 12:00:00Z]

    updated = Manifest.touch_generated_at(manifest, timestamp)
    assert updated["generated_at"] == "2025-10-08T12:00:00Z"
  end
end
