# ProcessWire DDEV Worktree Helper — Agent Guide

This tool provides `ddev-worktree.sh`, a helper that creates independent DDEV
environments inside git worktrees. It is designed for ProcessWire CMS but works
with any PHP application using DDEV.

## When you need this

You are in a git worktree (`.git` is a **file**, not a directory) and you need to:

- Run ProcessWire locally with a real database
- Test template changes, module code, or migrations against a working site
- Use ProcessWire CLI tools (AgentTools, migrations) in the worktree
- Run `ddev` commands (exec, ssh, import-db, etc.)

## What to do

### Starting from a bare worktree

```bash
bash ddev-worktree.sh setup
```

This single command runs init + start + import-db. After it completes the
ProcessWire site is available at `https://pw-<dirname>.ddev.site` with a copy
of the main project's database (pages, fields, templates, modules — everything).

### If DDEV is already initialized

```bash
bash ddev-worktree.sh start       # start containers
bash ddev-worktree.sh import-db   # refresh database from main project
```

### When done

```bash
bash ddev-worktree.sh destroy     # removes containers, database, and .ddev/
```

## How it works

The script reads the `.git` file to locate the main worktree, then:

1. **Creates `.ddev/`** with symlinks to the main project's shared DDEV config
   (PHP version, webserver type, database type, timezone, etc.)
2. **Generates `config.local.yaml`** that overrides the DDEV project name to
   something unique (e.g. `pw-shiny-harbor`)
3. **Generates `site/config-dev.php`** from the main worktree's template with:
   - Standard DDEV database credentials (`db`/`db`/`db`)
   - `$config->httpHosts` set to the worktree's DDEV URL
4. **For `setup`**: starts containers and exports the main project's database
   into the worktree using `ddev export-db` / `ddev import-db`

The worktree gets its own Docker containers and its own database — fully isolated
from the main project. Both `.ddev/` and `site/config-dev.php` are gitignored.

## Commands reference

| Command | When to use |
|---|---|
| `setup` | First time — bare worktree, no DDEV yet. Does init + start + import-db. |
| `init` | Create `.ddev/` config and `site/config-dev.php` without starting containers |
| `start` | Start existing DDEV project |
| `stop` | Stop containers (preserves database) |
| `import-db` | Refresh worktree database from main project |
| `snapshot-db` | Create a named database snapshot before risky changes |
| `destroy` | Remove DDEV project and `.ddev/` entirely |
| `status` | Show all worktree DDEV environments |

All commands accept an optional path argument (defaults to current directory).

## After setup: using ProcessWire in the worktree

Once `setup` completes, the full ProcessWire site is available. You can use
regular `ddev` commands from the worktree directory:

```bash
ddev exec php index.php --at-sitemap-generate     # AgentTools: regenerate sitemap
ddev exec php index.php --at-migrations-apply      # Apply pending migrations
ddev ssh                                            # Shell into web container
ddev import-db --file=dump.sql.gz                  # Import a custom database
ddev export-db --file=backup.sql.gz                # Export the worktree database
```

## ProcessWire-specific details

- The `site/config-dev.php` template is copied from the main worktree and
  `$config->httpHosts` is rewritten for the worktree's URL
- The project name prefix `pw-` is a convention (stands for ProcessWire)
- The script expects ProcessWire's standard directory layout (`site/config-dev.php`)

## Using with other PHP frameworks

The core mechanism works for any DDEV project. The ProcessWire-specific part
is the `site/config-dev.php` generation. For Laravel, WordPress, or plain PHP,
the script will warn about the missing template but continue — you just need
to provide your own framework-specific config file.
