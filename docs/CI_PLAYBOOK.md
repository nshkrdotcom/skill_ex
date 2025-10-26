# CI Playbook

The SkillEx CLI is designed to drop into any CI system. This guide outlines the common patterns for running the sync, publishing the archive, and surfacing issues early.

---

## Core Steps

Every pipeline follows the same high-level structure:

1. **Checkout repositories** – SkillEx plus each source repo listed in `manifest.json`.
2. **Install Elixir dependencies** – `mix deps.get`.
3. **Run tests** – `mix test` ensures aggregator logic still passes.
4. **Execute the sync script** – ideally with deterministic options (`--clock`, `--version`).
5. **Inspect JSON output** – fail the build if `status != "ok"`.
6. **Publish artifacts** – upload `dist/skills-pack-<version>.zip`, and optionally `manifest.json`.

The CLI output is machine-friendly JSON, so you can parse it in Bash, Elixir, or any scripting language available in your CI environment.

---

## GitHub Actions Example

```yaml
name: Skill Pack

on:
  workflow_dispatch:
  push:
    branches: [main]

jobs:
  build-pack:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4
        with:
          path: skill_ex

      # Checkout source repos (paths must match manifest.json)
      - uses: actions/checkout@v4
        with:
          repository: my-org/supertester
          path: supertester

      - name: Install Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.15'
          otp-version: '26'

      - name: Install deps
        working-directory: skill_ex
        run: mix deps.get

      - name: Test aggregator
        working-directory: skill_ex
        run: mix test

      - name: Sync skills
        working-directory: skill_ex
        run: >
          elixir scripts/sync_skills.exs
          --manifest manifest.json
          --target skills
          --package-script ../supertester/scripts/package_skill.py
          --clock ${{ github.event.head_commit.timestamp }}
          --version ${{ github.run_id }}
          | tee sync_output.json

      - name: Fail if sync reported errors
        working-directory: skill_ex
        run: |
          STATUS=$(jq -r '.status' sync_output.json)
          if [ "$STATUS" != "ok" ]; then
            cat sync_output.json
            exit 1
          fi

      - name: Upload skill pack
        uses: actions/upload-artifact@v4
        with:
          name: skills-pack
          path: |
            skill_ex/dist/skills-pack-${{ github.run_id }}.zip
            skill_ex/manifest.json
```

**Key Notes**

- `--package-script` can point to the packaging script in any checked-out repo.
- `--version` uses the GitHub run ID for uniqueness. Substitute build numbers or tags as needed.
- `jq` extracts values from the JSON output; any parser works if `jq` is unavailable.

---

## Buildkite / Other CI Systems

The same recipe applies:

```bash
mix deps.get
mix test

OUTPUT=$(elixir scripts/sync_skills.exs \
  --manifest manifest.json \
  --target skills \
  --package-script ../scripts/package_skill.py \
  --clock "$CI_TIMESTAMP" \
  --version "$CI_BUILD_NUMBER")

echo "$OUTPUT"

STATUS=$(echo "$OUTPUT" | jq -r '.status')
if [ "$STATUS" != "ok" ]; then
  exit 1
fi

buildkite-agent artifact upload "dist/skills-pack-$CI_BUILD_NUMBER.zip"
buildkite-agent artifact upload "manifest.json"
```

Replace `buildkite-agent` with the equivalent command in your CI.

---

## Tips & Best Practices

- **Cache Dependencies:** Use CI caching for `deps/` and `_build/` to keep runs fast.
- **Freeze Clocks in Tests:** When validating pipeline behaviour locally, pass `--clock` to produce deterministic timestamps.
- **Surface Summaries:** Pipe the JSON into your chat/alerting system so teams know what changed (e.g., newly added skills).
- **Parallel Builds:** If repos are large, checkout and validate skills in parallel stages before the final aggregation step.
- **Artifact Retention:** Retain both the zip and manifest so you can diff checksums across builds.
- **Security:** If the packaging script needs API keys, inject them via CI secrets and pass them through the CLI using environment variables.

---

Keeping the CI pipeline transparent ensures SkillEx does not become a mysterious black box. Adapt the snippets above to your build system, and update this playbook when you uncover better patterns.
