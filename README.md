# dotfiles

Cross-cluster shell utilities and Claude Code skills. Single source of
truth for the backup workflow that mirrors bulk project data to Google
Drive.

## Bootstrap on a new cluster

```bash
git clone git@github.com:demiranda-gabriel/dotfiles.git ~/dotfiles
~/dotfiles/bootstrap.sh
```

The bootstrap script is idempotent. It:

1. Symlinks every file in `bin/` into `~/.local/bin/`.
2. Appends a `source ~/dotfiles/shell/*.sh` line to `~/.bashrc` (only if
   absent).
3. Symlinks `claude/skills/*` into `~/.claude/skills/`.
4. Probes for `rclone`, `pigz`, and a configured `gdrive:` remote;
   reports anything missing.

After bootstrap, open a new shell (or `source ~/.bashrc`).

## Backup workflow

All bulk data lives under `gdrive:projects/<project>/<subpath>/<file>`.
Code stays in GitHub; only datasets, raw artefacts, and processed
outputs that need a long-term home off-cluster go to Drive.

| Command                                       | Behavior                                                                                |
|-----------------------------------------------|-----------------------------------------------------------------------------------------|
| `gdrive-push <local> [<sub>]`                 | `rclone copy <local> gdrive:projects/<proj>/<sub>/`                                     |
| `gdrive-pull <sub> [<dest>]`                  | inverse, into `<dest>` (default `.`)                                                    |
| `gdrive-archive <dir> [<sub>] [--rm] [-n]`    | tar + pigz, upload, **keep local by default** (`--rm` deletes after a successful copy)  |

`<proj>` is resolved from (first hit wins) the `-p` flag, the
`PROJECT_NAME` environment variable, or `basename(git rev-parse
--show-toplevel)`. Pass `-n` to any script to dry-run.

`gdrive-archive` honours an `ignore_list.txt` in the target directory
(`tar -X ignore_list.txt`) and uses `pigz` if available, gzip otherwise.

The shell snippet `shell/50-backup.sh` provides legacy aliases
`backup` / `restore` / `cloudsave` over the new scripts, so existing
muscle memory keeps working.

## Layout

```
dotfiles/
├── bin/                                 ← scripts symlinked into ~/.local/bin
│   ├── gdrive-push
│   ├── gdrive-pull
│   └── gdrive-archive
├── shell/                               ← sourced from ~/.bashrc by bootstrap
│   ├── 00-path.sh                       ← prepends ~/.local/bin to $PATH
│   └── 50-backup.sh                     ← backup / restore / cloudsave aliases
├── claude/skills/                       ← symlinked into ~/.claude/skills
│   └── backup-to-gdrive/SKILL.md        ← policy and triggers for Claude
├── rclone/rclone.conf.example           ← template; real config is per-cluster
└── bootstrap.sh
```

## Adding a new cluster

1. Install `rclone` and (optionally) `pigz` via the cluster's package
   manager or modules.
2. `git clone … ~/dotfiles && ~/dotfiles/bootstrap.sh`.
3. `rclone config` and create a remote named `gdrive` of type `drive`.
   On a headless cluster, run `rclone authorize drive` on a machine
   with a browser and paste the JSON token.
4. Smoke-test:
   ```bash
   echo hello > /tmp/hello.txt
   gdrive-push /tmp/hello.txt _smoketest -n     # dry-run
   gdrive-push /tmp/hello.txt _smoketest
   gdrive-pull _smoketest/hello.txt /tmp/hello.back
   diff /tmp/hello.txt /tmp/hello.back
   ```

## Security

`~/.config/rclone/rclone.conf` contains an OAuth refresh token. It is
listed in `.gitignore` and must never be committed. The
`rclone/rclone.conf.example` in this repo is a redacted template.
