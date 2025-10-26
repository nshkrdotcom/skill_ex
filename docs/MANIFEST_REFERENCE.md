# Manifest Reference

SkillEx centres around `manifest.json`. It defines the repositories that export skills and records metadata about the last successful sync. This page explains each field, validation rules, and extension opportunities.

---

## Top-Level Structure

```json
{
  "version": 1,
  "generated_at": "2025-10-08T12:00:00Z",
  "repositories": [ /* repo entries */ ],
  "skills": [ /* synced skill entries */ ]
}
```

### `version`

- **Type:** integer
- **Required:** yes
- **Purpose:** guards against breaking changes. Current value: `1`.
- **Future:** bump when the schema changes; use migrations to keep older manifests compatible.

### `generated_at`

- **Type:** ISO8601 timestamp as string or `null`
- **Required:** yes (but may be `null` before first sync)
- **Purpose:** records when the manifest was last updated by the sync script.
- **Behaviour:** updated automatically by `SkillEx.Manifest.touch_generated_at/2`. In dry-run mode the timestamp remains unchanged.

---

## `repositories` Array

Each entry describes a source repository that exports one or more skills.

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `name` | string | ✅ | Short identifier for the repo (used in output paths). |
| `path` | string | ✅ | Absolute or relative path to the repo root. Relative paths are resolved from the SkillEx project root. |
| `skills_dir` | string | optional | Location of the exported skills inside the repo. Defaults to `.claude/skills`. |

**Example:**

```json
{
  "name": "supertester",
  "path": "../supertester",
  "skills_dir": ".claude/skills"
}
```

**Validation Notes**

- The path must exist and be a directory. Missing paths raise `missing_repo`.
- The skills directory must exist and contain at least one subdirectory representing a skill. Missing directories raise `missing_skills_dir`.
- Multiple repositories may point to the same absolute path (e.g. mono-repo) provided `name` is unique.

---

## `skills` Array (Generated)

Entries represent each skill copied during the most recent sync. They are generated automatically; editing them manually is discouraged.

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `name` | string | ✅ | Skill directory name (e.g. `supertester-otp-testing`). |
| `source_repo` | string | ✅ | Matches the `name` field in the repositories array. |
| `target_path` | string | ✅ | Relative path inside the aggregated `skills/` directory. |
| `checksum` | string | ✅ | SHA-256 hash over all files in the skill directory (lowercase hex). |
| `packaged_at` | string | ✅ | ISO8601 timestamp when the skill passed validation and was copied. |

**Example Entry**

```json
{
  "name": "supertester-otp-testing",
  "source_repo": "supertester",
  "target_path": "supertester/supertester-otp-testing",
  "checksum": "71c13f90d52c7bb1bb257ea3087f2a1ebdf8a1084b4d04a745c9c371401b3f11",
  "packaged_at": "2025-10-08T12:00:00Z"
}
```

**Checksum Calculation**

- Files are enumerated deterministically (`Path.wildcard/2` with sort).
- Each file contributes both its relative path and contents to the hash.
- Any change in file content or layout updates the checksum, making it easy to detect drift.

**When Entries Update**

- During a successful sync, each skill entry is replaced (if it already exists) or appended.
- If sync fails for a repo, corresponding entries remain unchanged (checksum still reflects last good run).
- Dry-run mode skips modifications entirely.

---

## Extending the Manifest

Fields that the schema tolerates but currently ignores can still be stored—the aggregator passes unknown keys through.

### Recommendations

- **`branch` / `commit`**: capture git state per repository. Useful for traceability in multi-branch workflows.
- **`validator`**: allow per-repo override for the command to run.
- **`notes`**: free-form string for human hints (“requires VPN”, “large assets”).
- **`skill_metadata`**: nested object keyed by skill name for supplementary instructions.

When adding new fields:

1. Update this document with the intent and format.
2. Introduce tests to ensure the aggregator handles the new fields safely.
3. Consider version bumps if the change impacts automation or parsing logic.

---

## FAQ

**Q: Can I store network paths (SMB/NFS) in `path`?**  
A: Yes, as long as the runtime environment can access them. Ensure CI has the necessary mounts or credentials.

**Q: What happens if two repos export a skill with the same name?**  
A: The aggregator stores each under `<repo-name>/<skill-name>`. As long as repo names differ, there is no collision.

**Q: How do I remove a skill permanently?**  
A: Remove the repo entry or delete the skill directory inside a repo, run sync again, and commit the manifest/skills changes. Old entries are replaced with the current state.

**Q: Can a repo export multiple skills?**  
A: Yes. Each subdirectory within `.claude/skills` is treated as a separate skill. All will be copied and validated.

---

Keep this reference current as the schema evolves so anyone reading the manifest understands every field at a glance.
