# User-scoped instructions

Loaded for every Claude Code session under this home directory,
regardless of project.

## Backup / cross-cluster data workflow

Bulk data (datasets, raw artefacts, run outputs that are too large for
git) lives on Google Drive under the layout
`gdrive:projects/<project>/<subpath>/<filename>`. Code goes to GitHub;
only files that need a durable off-cluster home go to Drive.

Three scripts implement the contract (installed by
`~/dotfiles/bootstrap.sh` into `~/.local/bin/`):

| Command          | Purpose                                                         |
|------------------|-----------------------------------------------------------------|
| `gdrive-push`    | `rclone copy` a path to `gdrive:projects/<proj>/<sub>/`         |
| `gdrive-pull`    | inverse                                                         |
| `gdrive-archive` | tar + pigz a directory, upload, keep local by default (`--rm` to delete) |

Project name auto-resolves from `basename(git rev-parse --show-toplevel)`,
overridable via `-p` or `$PROJECT_NAME`. All three accept `-n` for
dry-run. Use dry-run first for anything large or when the destination
subpath is new.

Detailed policy (when to invoke, restore flow, ignore_list.txt rules)
lives in the `backup-to-gdrive` skill. The skill is the authoritative
source — this section is just a pointer.

The same dotfiles repo (`~/dotfiles`, `git@github.com:demiranda-gabriel/dotfiles.git`)
is the single source of truth across every cluster I work on. Run
`~/dotfiles/bootstrap.sh` once per cluster after cloning.
