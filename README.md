# ProcessWire DDEV Worktree Helper

Bash script to run independent [DDEV](https://ddev.readthedocs.io/) environments inside git worktrees — purpose-built for [ProcessWire CMS/CMF](https://processwire.com/) development.

One command to go from a bare worktree to a fully working local ProcessWire dev server with database.

## Why this exists

ProcessWire projects use DDEV for local development. DDEV identifies a project by the `.ddev/` directory location and bind-mounts that directory's parent as the web root. Since `.ddev/` is gitignored and only exists in the main worktree, any git worktree has no DDEV environment — you can't test code changes locally without merging back to the main branch.

ProcessWire adds an extra wrinkle: the `site/config-dev.php` file (also gitignored) contains DDEV database credentials and an `httpHosts` whitelist that must match the DDEV URL. A worktree needs its own copy with the correct hostname.

This script handles all of that automatically.

## What it does

`ddev-worktree.sh` creates a **separate DDEV project** inside each worktree:

1. Creates a `.ddev/` directory with **symlinks** to the main worktree's shared DDEV config (PHP version, webserver type, database type, timezone, etc.)
2. Generates a `config.local.yaml` with a unique DDEV project name
3. Generates a `site/config-dev.php` from the main worktree's template, with the worktree's DDEV URL in `httpHosts`
4. For `setup`: starts containers and copies the main project's database into the worktree

Each worktree gets its own URL, its own database container, and full isolation from the main project.

```
Main worktree:  ~/www/processwire.md/
  .ddev/config.yaml                        ← shared settings (PHP 8.4, Apache, MariaDB)
  site/config-dev.php                      ← template with DDEV credentials

Worktree:       ~/worktrees/my-feature/
  .ddev/
    config.yaml          → symlink to main
    config.local.yaml    ← name: pw-my-feature (auto-generated)
  site/config-dev.php    ← httpHosts includes pw-my-feature.ddev.site
```

### ProcessWire-specific behavior

- Copies `site/config-dev.php` from the main worktree and rewrites `$config->httpHosts` to include the worktree's DDEV URL
- Database credentials stay standard DDEV defaults (`db`/`db`/`db`) — no changes needed
- After `setup`, the full ProcessWire site is available with all pages, fields, templates, and modules intact

## Requirements

- [DDEV](https://ddev.readthedocs.io/) v1.24+ (tested with v1.25.2)
- A main worktree with a working `.ddev/` configuration
- A `site/config-dev.php` in the main worktree with DDEV database credentials (used as template)

## Installation

### As a git submodule (recommended)

```bash
git submodule add https://github.com/webmanufaktur/processwire-ddev-worktree.git ddev-worktree
```

### Standalone

```bash
curl -O https://raw.githubusercontent.com/webmanufaktur/processwire-ddev-worktree/main/ddev-worktree.sh
chmod +x ddev-worktree.sh
```

## Quick Start

```bash
# From inside any git worktree — one command to get a working ProcessWire environment:
./ddev-worktree.sh setup
```

This runs `init` + `start` + `import-db` in sequence.

Or run each step individually:

```bash
./ddev-worktree.sh init        # create .ddev/ config and site/config-dev.php
./ddev-worktree.sh start       # start containers
./ddev-worktree.sh import-db   # copy database from main project
```

You can also pass a path explicitly:

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
| `import-db [PATH]` | Export the main project's database and import it into the worktree. |
| `snapshot-db [PATH]` | Create a named DDEV database snapshot in the worktree. |
| `destroy [PATH]` | Remove the DDEV project and `.ddev/` from the worktree. Prompts for confirmation. |
| `status` | Scan all git worktrees and show which ones have DDEV environments. |

All commands except `status` accept an optional `WORKTREE_PATH` argument that defaults to the current working directory.

## How It Works

### Project Name Derivation

The project name is derived from the worktree's directory name, lowercased and sanitized, with a `pw-` prefix:

| Worktree directory | DDEV project name | URL |
|---|---|---|
| `shiny-harbor` | `pw-shiny-harbor` | `https://pw-shiny-harbor.ddev.site` |
| `fix/seo-migration` | `pw-seo-migration` | `https://pw-seo-migration.ddev.site` |

### Symlinked Files

Shared config is symlinked from the main worktree's `.ddev/` so settings stay in sync:

- `config.yaml` (PHP version, webserver type, database type, timezone, etc.)
- `apache-site.conf` / `nginx-site.conf` (if present)
- `php/` directory (custom PHP configurations, if present)

### Auto-Generated Files

Created fresh in the worktree — both are gitignored by default:

- `.ddev/config.local.yaml` — overrides the DDEV project name
- `site/config-dev.php` — DDEV database credentials with the worktree's URL in `httpHosts`

### Database Isolation

Each worktree gets its own MariaDB container. Use `setup` to automatically copy the main project's database. Re-run `import-db` at any time to refresh.

## Typical Workflow

```bash
# 1. Create a worktree (e.g. via opencode, gh, or manually)
git worktree add ../my-feature feature-branch

# 2. One command — fully working ProcessWire environment with database
./ddev-worktree.sh setup ../my-feature

# 3. Open in browser and start working
open https://pw-my-feature.ddev.site

# 4. Run ProcessWire CLI tools inside DDEV
cd ../my-feature
ddev exec php index.php --at-sitemap-generate

# 5. Refresh the database from main at any time
./ddev-worktree.sh import-db ../my-feature

# 6. When done, clean up
./ddev-worktree.sh destroy ../my-feature
git worktree remove ../my-feature
```

## Using with other frameworks

While designed for ProcessWire, the core mechanism — symlinking shared DDEV config and creating an isolated project per worktree — works for any PHP application. The ProcessWire-specific part is the `site/config-dev.php` generation with `httpHosts` rewriting.

For other frameworks:

- **Laravel**: replace the `config-dev.php` step with a `.env` file that sets `DB_HOST=db`, `DB_DATABASE=db`, `DB_USERNAME=db`, `DB_PASSWORD=db`, and `APP_URL=https://pw-my-feature.ddev.site`
- **Plain PHP**: the script works as-is — just skip the `config-dev.php` step (it warns but continues)
- **WordPress**: create a `wp-config.php` with `DB_HOST=db`, `DB_USER=db`, `DB_PASSWORD=db` and set `WP_HOME`/`WP_SITEURL` to the worktree's DDEV URL

The `pw-` prefix on project names is a convention — you can change it in the `sanitize_project_name()` function.

## Limitations

- The main worktree must have a `.ddev/` directory set up before running `init`.
- `import-db` requires the main project's DDEV to be running (to export from it). `setup` starts it automatically if needed.
- Each worktree consumes its own pair of Docker containers (web + db). Running many worktrees simultaneously uses more resources.
- The script is designed for git worktrees (where `.git` is a file, not a directory). It will refuse to run in the main worktree.

## License

[MPL-2.0](https://www.mozilla.org/en-US/MPL/2.0/)
