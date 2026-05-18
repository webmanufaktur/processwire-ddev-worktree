# DDEV Worktree Helper — Agent Guide

This tool provides `ddev-worktree.sh`, a helper that creates independent DDEV
environments inside git worktrees. Use it when you are working in a worktree that has
no `.ddev/` directory and needs a local development server with a database.

## When you need this

You are in a git worktree (`.git` is a **file**, not a directory) and you need to:

- Run ProcessWire or any PHP application locally
- Test changes against a real database
- Use `ddev` commands (import-db, exec, ssh, etc.)

## What to do

### Starting from a bare worktree

```bash
bash ddev-worktree.sh setup
```

This single command runs init + start + import-db. After it completes the site is
available at `https://pw-<dirname>.ddev.site` with a copy of the main project's
database. You can start working immediately.

### If DDEV is already initialized

```bash
bash ddev-worktree.sh start       # start containers
bash ddev-worktree.sh import-db   # refresh database from main project
```

### When done

```bash
bash ddev-worktree.sh destroy     # removes containers and .ddev/
```

## How it works

The script reads `.git` to find the main worktree, then:

1. Creates `.ddev/` with **symlinks** to the main project's shared DDEV config
   (PHP version, webserver type, database type, etc.)
2. Generates a `config.local.yaml` that overrides the project name to something
   unique (e.g. `pw-shiny-harbor` → URL `https://pw-shiny-harbor.ddev.site`)
3. Generates a `site/config-dev.php` with the worktree's URL in `httpHosts`
4. For `setup`: starts containers and exports the main project's database into
   the worktree using `ddev export-db` / `ddev import-db`

The worktree gets its own Docker containers and its own database — fully isolated
from the main project.

## Commands reference

| Command | When to use |
|---|---|
| `setup` | First time — bare worktree, no DDEV yet |
| `init` | Create `.ddev/` config without starting containers |
| `start` | Start existing DDEV project |
| `stop` | Stop containers (preserves database) |
| `import-db` | Refresh worktree database from main project |
| `snapshot-db` | Create a named database snapshot |
| `destroy` | Remove DDEV project and `.ddev/` entirely |
| `status` | Show all worktree DDEV environments |

All commands accept an optional path argument (defaults to current directory).

## Important details

- The main project's DDEV must be running for `import-db` and `setup` to work.
  `setup` will start it automatically if needed.
- `.ddev/` and `site/config-dev.php` are gitignored — they will never appear in
  commits.
- The project name is derived from the worktree directory name with a `pw-` prefix.
- Each worktree consumes its own pair of Docker containers (web + db).

## After setup: using the worktree DDEV

Once `setup` completes, you can use regular `ddev` commands from the worktree:

```bash
ddev exec php index.php --at-sitemap-generate     # run AgentTools
ddev ssh                                            # shell into web container
ddev import-db --file=dump.sql.gz                  # import a custom database
ddev export-db --file=backup.sql.gz                # export the worktree database
```

## Integration: as a submodule

When installed as a git submodule, the script is typically available at:

```bash
bash ddev-worktree/ddev-worktree.sh setup
```

Adjust the path based on where the submodule is placed in the parent project.
