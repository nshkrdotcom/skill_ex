defmodule SkillEx.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/supertester/tree/main/skill_ex"

  def project do
    [
      app: :skill_ex,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
      name: "SkillEx",
      source_url: @source_url,
      homepage_url: @source_url,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        "coveralls.post": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false}
    ]
  end

  defp description do
    """
    Aggregates and packages Claude skills from multiple Elixir projects into a single, validated bundle ready for distribution.
    """
  end

  defp docs do
    [
      main: "readme",
      name: "SkillEx",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      assets: %{"logo" => "logo"},
      logo: "logo/skill_ex.svg",
      extras: [
        "README.md",
        "docs/WORKFLOW.md",
        "docs/MANIFEST_REFERENCE.md",
        "docs/CI_PLAYBOOK.md",
        "docs/20251025/FUTURE_VISION.md"
      ],
      groups_for_extras: [
        Guides: ["README.md", "docs/WORKFLOW.md"],
        Reference: ["docs/MANIFEST_REFERENCE.md"],
        Operations: ["docs/CI_PLAYBOOK.md"],
        Strategy: ["docs/20251025/FUTURE_VISION.md"]
      ]
    ]
  end

  defp package do
    [
      name: "skill_ex",
      description: description(),
      files: ~w(lib mix.exs README.md LICENSE docs manifest.json scripts logo/skill_ex.svg),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Documentation" => "https://hexdocs.pm/skill_ex"
      },
      maintainers: ["nshkrdotcom"]
    ]
  end
end
