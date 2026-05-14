---
name: backup-to-gdrive
description: Tar-and-upload bulk project data (datasets, run outputs, raw artefacts) to Google Drive via the gdrive-push, gdrive-pull, and gdrive-archive scripts. Use when the user says "back this up", "upload to gdrive", "cloudsave", "snapshot the data folder", "free up disk", or asks to mirror a directory off-cluster. Pulls (restores) trigger on "restore from gdrive", "pull the backup", "fetch from drive". The scripts must already be on PATH (bootstrapped from ~/dotfiles).
---

# backup-to-gdrive

Wraps three scripts installed by `~/dotfiles/bootstrap.sh`:

| Script           | Purpose                                                      |
|------------------|--------------------------------------------------------------|
| `gdrive-push`    | rclone copy a file/dir to `gdrive:projects/<proj>/<sub>/`    |
| `gdrive-pull`    | inverse: download from `gdrive:projects/<proj>/<sub>/`       |
| `gdrive-archive` | tar+pigz a directory, upload, optionally remove local archive |

All three resolve `<proj>` from (in order): `-p` flag, `$PROJECT_NAME`, or
`basename(git rev-parse --show-toplevel)`. The remote layout is fixed:
**`gdrive:projects/<project>/<sub>/<filename>`**.

## When to invoke

Use this skill when the user:

- asks to back up, archive, snapshot, mirror, or upload a directory to
  Google Drive
- talks about freeing disk space on a cluster and the data is too big to
  keep locally
- references the old `backup` / `cloudsave` / `tarx` shell functions
- asks to restore / pull / fetch a previously archived directory

Do **not** invoke for:

- code or text files that belong in the git repo — those go to GitHub
- ephemeral logs that can be regenerated — let them die

## Default policy

1. **Tarball goes to gdrive, source code goes to git.** If the user
   wants to back up something tracked by git, redirect them to commit
   and push instead.
2. **Keep the local archive by default.** Pass `--rm` to delete after a
   successful upload — only do that when the user explicitly asks to
   free space.
3. **Confirm before any deletion.** Never `--rm` without an explicit
   instruction in the conversation.
4. **Dry-run first** for anything > a few GB or when the destination
   subpath is new. Show the user the planned `rclone` command from
   `-n` output before executing.
5. **Honour `ignore_list.txt`.** If the target directory has one,
   `gdrive-archive` will pick it up automatically. If the directory has
   obvious junk (`__pycache__`, `.venv`, lockfiles), suggest writing or
   updating `ignore_list.txt` before archiving.

## Typical flows

### Archive a project's data directory

```bash
gdrive-archive data experiments_data           # data/ → projects/<proj>/experiments_data/data-YYYY-MM-DD.tar.gz
```

### Push a single processed file

```bash
gdrive-push outputs/results.parquet outputs    # → projects/<proj>/outputs/results.parquet
```

### Restore from a new cluster

```bash
gdrive-pull experiments_data/data-2026-05-14.tar.gz
tar -xzf data-2026-05-14.tar.gz -C data/
```

### Override project name

```bash
gdrive-archive shared_models models -p shared-assets
```

## Verifying before you run

Before invoking a script for the user, sanity-check:

- `command -v gdrive-archive` returns a path (else: bootstrap not run)
- `rclone listremotes` includes `gdrive:` (else: run `rclone config`)
- For `--rm` invocations, the user has explicitly authorized deletion
- For multi-GB uploads, the user is aware (mention the size first)

## Restore-time discipline

When restoring on a new cluster:

1. Run `gdrive-pull` into a clean directory.
2. Verify checksum / file count against what's expected.
3. Only then extract and wire it into the project.
4. Never overwrite an existing local directory without asking.
