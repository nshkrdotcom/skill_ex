# SkillEx Workflow Guide

This document walks through the end-to-end process for keeping Claude skills organised across all Elixir repos using SkillEx. Treat it as the playbook for onboarding new repositories and for the day-to-day rituals that keep the aggregated pack healthy.

---

## 1. Prerequisites

- Elixir ≥ 1.14 (matching whichever version is used in the repos you are aggregating).
- Each source repository exposes its skill under `.claude/skills/<skill-name>/`.
- A shared validator/package script is available (e.g. `scripts/package_skill.py`) that enforces the SKILL.md requirements.
- SkillEx cloned locally or available in CI.

Optional but recommended:

- Git access to all source repositories.
- CI pipeline with permission to publish artifacts (see [CI Playbook](CI_PLAYBOOK.md)).

---

## 2. Onboard a Repository

1. **Create or verify the skill directory**  
   Inside the source repo:
   ```
   .claude/
     skills/
       <repo-skill>/
         SKILL.md
         references/
         scripts/
   ```
   Run the repo’s validator to confirm the skill passes on its own.

2. **Add the repo to SkillEx manifest**  
   Open `manifest.json` and append an entry under `repositories`:
   ```json
   {
     "name": "supertester",
     "path": "../supertester",
     "skills_dir": ".claude/skills"
   }
   ```
   Paths may be relative to the SkillEx project root or absolute. Commit the change.

3. **(Optional) Stage additional metadata**  
   If you want the manifest to record extra context (branch, git URL), note it for later. The manifest schema can evolve without breaking existing tooling—capture TODOs in issues or docs.

---

## 3. Run the Sync

### Dry Run

Always start with a dry run to discover what SkillEx will attempt.

```bash
elixir scripts/sync_skills.exs \
  --manifest manifest.json \
  --target skills \
  --package-script ../scripts/package_skill.py \
  --dry-run
```

The script prints a JSON payload shaped like:
```json
{
  "status": "ok",
  "summary": {
    "planned": 2,
    "copied": 0,
    "validated": 0,
    "errors": [],
    "timestamp": "2025-10-08T12:00:00Z"
  },
  "target": "/path/to/skill_ex/skills"
}
```

Review this before committing to a real sync. If `status` is `"error"` or `errors` is non-empty, address those issues first.

### Real Run

When ready:

```bash
elixir scripts/sync_skills.exs \
  --manifest manifest.json \
  --target skills \
  --package-script ../scripts/package_skill.py
```

The script will:

1. Copy each skill into `skills/<repo-name>/<skill-name>/`.
2. Validate the copied skill using the provided script.
3. Update `manifest.json` with fresh timestamps and checksums.
4. Emit a zip at `dist/skills-pack-<date>.zip`.

Carry out a quick sanity check:

- Confirm the copied SKILL.md matches the source.
- Open `manifest.json` and ensure checksums changed when expected.
- Inspect the output zip with `unzip -l dist/skills-pack-*.zip`.

---

## 4. Typical Daily Loop

1. Pull latest SkillEx.
2. Update manifest or skill repos as needed.
3. Run `mix test` to ensure the core logic still passes.
4. Execute the sync script (dry-run first).
5. Commit the updated manifest and any new docs or scripts.
6. Push and let CI publish the new `skills-pack` artifact.

---

## 5. Troubleshooting

| Symptom | Likely Cause | Suggested Fix |
| --- | --- | --- |
| `missing_repo` error | `path` in manifest is wrong or repo not checked out | Check out the repo or adjust the path. |
| `missing_skills_dir` error | Repo lacks `.claude/skills` | Ensure the repo exports a skill or disable the entry. |
| Validation failures | Validator exited non-zero | Run the validator manually inside the repo to diagnose. |
| Zip archive empty | Repos copied but packaging ran before files existed | Make sure validator doesn’t delete files; rerun sync. |
| Manifest not updating | Dry-run flag still enabled | Remove `--dry-run` for actual syncs. |

If issues persist, run the CLI with `--clock` to freeze timestamps and re-run tests (`mix test`) to reproduce failures locally.

---

## 6. Extending the System

- **Repo-specific validators**: Accept a map of validator commands keyed by repo name.
- **Incremental sync**: Skip repositories whose checksums are unchanged.
- **Git metadata**: Record commit SHA or tags in the manifest skill entries.
- **Notifications**: Hook into chat/Slack when errors occur, using the JSON CLI output.

Capture decisions in new docs or issues so the workflow remains discoverable.

---

Happy aggregating! If you discover improvements, update this document so the next pass is even smoother.
