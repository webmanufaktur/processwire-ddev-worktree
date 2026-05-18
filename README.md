# DDEV Git Worktree Helper

Bash script to run independent [DDEV](https://ddev.readthedocs.io/) environments inside git worktrees.

One command to go from a bare worktree to a fully working local dev server with database.

## The Problem

DDEV identifies a project by the `.ddev/` directory location and bind-mounts that directory's parent as the web root inside the container. Since `.ddev/` is gitignored and only exists in the main worktree, any git worktree created from the repository has no DDEV environment — code changes in the worktree cannot be tested locally without merging back to the main branch first.

## The Solution

`ddev-worktree.sh` creates a **separate DDEV project** inside each worktree by:

1. Creating a `.ddev/` directory in the worktree
2. Symlinking shared config files (PHP version, webserver type, etc.) from the main worktree
3. Generating a `config.local.yaml` with a unique project name
4. Generating a `site/config-dev.php` with the correct `httpHosts` for the worktree's URL

Each worktree gets its own URL, its own database container, and full isolation from the main project.

```
Main worktree:  ~/www/my-project/
  .ddev/config.yaml                        ← shared settings

Worktree:       ~/worktrees/feature-x/
  .ddev/
    config.yaml          → symlink to main
    config.local.yaml    ← name: pw-feature-x (auto-generated)
  site/config-dev.php    ← httpHosts includes pw-feature-x.ddev.site
```

## Requirements

- [DDEV](https://ddev.readthedocs.io/) v1.24+ (tested with v1.25.2)
- A main worktree with a working `.ddev/` configuration
- The main worktree should have a `site/config-dev.php` with DDEV database credentials (used as template)

## Installation

### As a git submodule (recommended)

```bash
git submodule add https://github.com/webmanufaktur/ddev-worktree.git ddev-worktree
```

### Standalone

```bash
curl -O https://raw.githubusercontent.com/webmanufaktur/ddev-worktree/main/ddev-worktree.sh
chmod +x ddev-worktree.sh
```

## Quick Start

```bash
# From inside any git worktree — one command to get a working environment:
./ddev-worktree.sh setup
```

This runs `init` + `start` + `import-db` in sequence.

Or run each step individually:

```bash
./ddev-worktree.sh init        # set up DDEV config
./ddev-worktree.sh start       # start containers
./ddev-worktree.sh import-db   # copy database from main project
```

You can also pass a path explicitly to any command:

```bash
./ddev-worktree.sh setup /path/to/worktree
```

## Commands

| Command | Description |
|---|---|
| `setup [PATH]` | **One-shot**: init + start + import database. Gets you from a bare worktree to a fully working environment. Starts the main project's DDEV too if needed. |
| `init [PATH]` | Set up DDEV in a worktree. Symlinks shared config, generates `config.local.yaml` and `site/config-dev.php`. |
| `start [PATH]` | Start the worktree's DDEV containers. |
| `stop [PATH]` | Stop the worktree's DDEV containers. |
| `import-db [PATH]` | Export the main project's database and import it into the worktree. Requires the main project's DDEV to be running. |
| `snapshot-db [PATH]` | Create a named DDEV database snapshot in the worktree. |
| `destroy [PATH]` | Remove the DDEV project and `.ddev/` from the worktree. Prompts for confirmation. |
| `status` | Scan all git worktrees and show which ones have DDEV environments. |

All commands except `status` accept an optional `WORKTREE_PATH` argument that defaults to the current working directory.

## How It Works

### Project Name Derivation

The project name is derived from the worktree's directory name, lowercased and sanitized, with a `pw-` prefix. For example:

| Worktree directory | DDEV project name | URL |
|---|---|---|
| `shiny-harbor` | `pw-shiny-harbor` | `https://pw-shiny-harbor.ddev.site` |
| `fix/seo-migration` | `pw-seo-migration` | `https://pw-seo-migration.ddev.site` |

### Symlinked Files

These files are symlinked from the main worktree's `.ddev/` so shared settings stay in sync:

- `config.yaml` (PHP version, webserver type, database type, timezone, etc.)
- `apache-site.conf` / `nginx-site.conf` (if present)
- `php/` directory (custom PHP configurations, if present)

### Auto-Generated Files

These files are created fresh in the worktree and are gitignored:

- `.ddev/config.local.yaml` — overrides the project name
- `site/config-dev.php` — DDEV database credentials with the worktree's URL in `httpHosts`

### Database Isolation

Each worktree gets its own MariaDB container with an empty database. Use `setup` (which includes `import-db`) to automatically copy the main project's database into the worktree. You can also re-run `import-db` at any time to refresh the worktree's database.

## Typical Workflow

```bash
# 1. Create a worktree (e.g. via opencode, gh, or manually)
git worktree add ../my-feature feature-branch

# 2. One command to get a fully working environment with database
./ddev-worktree.sh setup ../my-feature

# 3. Open in browser and start working
open https://pw-my-feature.ddev.site

# 4. Refresh the database from main at any time
./ddev-worktree.sh import-db ../my-feature

# 5. When done, clean up
./ddev-worktree.sh destroy ../my-feature
git worktree remove ../my-feature
```

## Limitations

- The main worktree must have a `.ddev/` directory set up before running `init`.
- `import-db` requires the main project's DDEV to be running (to export from it).
- Each worktree consumes its own set of Docker containers (web + db). Running many worktrees simultaneously uses more resources.
- The script is designed for git worktrees (where `.git` is a file, not a directory). It will refuse to run in the main worktree.

## License

[MPL-2.0](https://www.mozilla.org/en-US/MPL/2.0/)
