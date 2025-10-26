<div align="center">
  <img src="logo/skill_ex.svg" alt="SkillEx Logo" width="200"/>
</div>

# SkillEx – Claude Skill Aggregator

[![Hex.pm](https://img.shields.io/hexpm/v/skill_ex.svg)](https://hex.pm/packages/skill_ex)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-purple.svg)](https://hexdocs.pm/skill_ex)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/nshkrdotcom/supertester/blob/main/skill_ex/LICENSE)

SkillEx is our hub for collecting `.claude/skills` directories from every Elixir repo, validating them, and packaging a single `skills-pack-<date>.zip` that Claude can load in one go. Each application owns the content of its skill, while SkillEx keeps the packs fresh and consistent.

---

## Why SkillEx Exists

- **One-stop distribution** – No more hunting through repos; the pack contains every published skill.
- **Consistent validation** – Every skill runs through the same packaging/validation script before inclusion.
- **Repeatable automation** – The CLI emits JSON so CI pipelines can publish artifacts or fail fast on issues.
- **Change tracking** – The manifest captures checksums and timestamps so we know what shipped and when.

---

## Quick Start

```bash
# Install deps and run the test suite
mix deps.get
mix test

# Review or edit the manifest
cat manifest.json

# Run a sync using the script (dry run shown)
elixir scripts/sync_skills.exs \
  --manifest manifest.json \
  --target skills \
  --dry-run
```

The script reports a JSON summary and (when not in dry-run) copies every discovered skill into `skills/<repo>/<skill-name>/`, runs validation, updates `manifest.json`, and emits a packaged zip under `dist/`.

---

## Repository Layout

```
skill_ex/
├── lib/
│   ├── skill_ex/aggregator.ex      # Sync, validation, packaging logic
│   └── skill_ex/manifest.ex        # Manifest load/save helpers
├── scripts/sync_skills.exs         # CLI that drives the aggregator
├── skills/                         # Output directory populated by sync
├── dist/                           # Final zipped packs (created on demand)
├── manifest.json                   # Declares upstream repos and tracks sync metadata
├── docs/                           # Extended documentation (workflow, manifest, CI)
├── test/                           # ExUnit suites & helpers (pure TDD coverage)
└── logo/skill_ex.svg               # Project badge for docs/dashboards
```

---

## Core Components

| Component | Responsibility |
| --- | --- |
| `SkillEx.Manifest` | Load/save JSON manifest, manage `skills` entries, timestamp updates. |
| `SkillEx.Aggregator` | Copy skills out of repos, call validators, compute checksums, package archives, and refresh the manifest. |
| `scripts/sync_skills.exs` | Thin CLI wrapper. Parses flags, loads repos from the manifest, invokes the aggregator, prints JSON for CI usage. |
| `test/support/test_helpers.exs` | Fixture helpers (temp dirs, fake repos, stub validators) used across tests. |

Implementation details and extension ideas live in the docs directory—start with [`docs/WORKFLOW.md`](docs/WORKFLOW.md).

---

## Running the Sync Script

```
elixir scripts/sync_skills.exs \
  --manifest path/to/manifest.json \
  --target path/to/output/skills \
  --package-script path/to/scripts/package_skill.py \
  [--dry-run] \
  [--clock 2025-10-08T12:00:00Z] \
  [--version 2025.10.08]
```

### Flags

| Flag | Required | Description |
| --- | --- | --- |
| `--manifest` | ✅ | Manifest file to read/write. Determines which repos export skills. |
| `--target` | ✅ | Directory that should contain synced skills. Created if missing. |
| `--package-script` | ✅ (unless validator provided) | External validator/packager (typically `scripts/package_skill.py`). |
| `--dry-run` | Optional | Reports what *would* happen without copying or packaging. |
| `--clock` | Optional | ISO8601 timestamp used for deterministic runs/tests. Defaults to `DateTime.utc_now/0`. |
| `--version` | Optional | Overrides the archive suffix (`skills-pack-<version>.zip`). Useful in CI. |

The script exits with `0` for success and `1` when sync/validation encounters errors. Output is always JSON so downstream steps can parse it reliably.

---

## Manifest Overview

The manifest ties everything together. It tracks **which repos export skills** and stores **metadata about the last successful sync**.

```json
{
  "version": 1,
  "generated_at": "2025-10-08T12:00:00Z",
  "repositories": [
    {
      "name": "supertester",
      "path": "../supertester",
      "skills_dir": ".claude/skills"
    }
  ],
  "skills": [
    {
      "name": "supertester-otp-testing",
      "source_repo": "supertester",
      "target_path": "supertester/supertester-otp-testing",
      "checksum": "01ab...ff",
      "packaged_at": "2025-10-08T12:00:00Z"
    }
  ]
}
```

Every field is documented in [`docs/MANIFEST_REFERENCE.md`](docs/MANIFEST_REFERENCE.md), including optional keys and gotchas (network paths, symlinks, etc.).

---

## Typical Workflow

1. **Prepare source repos**  
   - Each repo houses its skill under `.claude/skills/<repo-skill>/SKILL.md`.  
   - Ensure the repo’s own validator (usually `scripts/package_skill.py`) succeeds locally.
2. **Update `manifest.json`**  
   - Add repo entries (absolute or relative paths).  
   - Commit the manifest change back to SkillEx.
3. **Run the CLI**  
   - Dry-run first to audit the operations (`planned` count).  
   - Run without `--dry-run` to copy, validate, and write the bundle.
4. **Inspect outputs**  
   - Check `skills/<repo>/<skill>/` to confirm the expected files.  
   - Review the JSON summary and updated manifest for checksum/timestamp changes.  
   - Find the zipped artifact under `dist/skills-pack-<date>.zip`.
5. **Automate**  
   - CI can invoke the script, parse JSON, and upload the archive as a build artifact.  
   - See [`docs/CI_PLAYBOOK.md`](docs/CI_PLAYBOOK.md) for ideas.

The ExUnit suite mirrors this flow with deterministic temp repos so regressions are caught quickly.

---

## Development & Testing

| Task | Command |
| --- | --- |
| Run entire test suite | `mix test` |
| Format stubs or generated manifests | `mix format` |
| Execute only aggregator tests | `mix test test/skill_ex/aggregator_test.exs` |
| Run script tests (integration style) | `mix test test/scripts/sync_skills_script_test.exs` |

All tests are written first (true TDD). When expanding the system:

- **Add tests before implementation** for new behaviours (new validator modes, multi-root targets, etc.).
- **Use test helpers** to keep fixtures tidy.
- **Prefer pure functions** (clock injection, custom validator) to keep tests deterministic.

---

## Roadmap & Ideas

- Surface git metadata (repo SHA, branch) in manifest skill entries.
- Allow repo-specific validator overrides instead of one global `--package-script`.
- Support incremental packaging (skip unchanged skills based on checksum).
- Publish checksum diff reports to highlight what changed between packs.
- Add optional `references/` ingestion to capture documentation bundles.

If you explore any of these, drop a note in the docs so future developers know the plan.

---

## Learn More

- [`docs/WORKFLOW.md`](docs/WORKFLOW.md) – Deep dive into onboarding repos and daily operation.
- [`docs/MANIFEST_REFERENCE.md`](docs/MANIFEST_REFERENCE.md) – Field-by-field schema with pitfalls and examples.
- [`docs/CI_PLAYBOOK.md`](docs/CI_PLAYBOOK.md) – Suggestions for wiring SkillEx into GitHub Actions, Buildkite, or GitLab.

## 📄 License

This project is licensed under the MIT License – see the [LICENSE](https://github.com/nshkrdotcom/supertester/blob/main/skill_ex/LICENSE) file for details.

Questions? Share findings or improvements in the repo so the next engineer has an even smoother ride.
