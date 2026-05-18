#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# ddev-worktree.sh — Manage DDEV environments for git worktrees
#
# Commands:
#   setup [WORKTREE_PATH]      One-shot: init + start + import database from main
#   init [WORKTREE_PATH]       Set up DDEV in a worktree (symlink shared config)
#   start [WORKTREE_PATH]      Start the worktree's DDEV project
#   stop [WORKTREE_PATH]       Stop the worktree's DDEV project
#   import-db [WORKTREE_PATH]  Copy database from the main project
#   snapshot-db [WORKTREE_PATH] Create a DDEV snapshot of the worktree DB
#   destroy [WORKTREE_PATH]    Remove DDEV project and .ddev/ from the worktree
#   status                     List all worktree DDEV environments
# =============================================================================

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()    { printf "${BLUE}  ℹ %s${NC}\n" "$*"; }
ok()      { printf "${GREEN}  ✔ %s${NC}\n" "$*"; }
warn()    { printf "${YELLOW}  ⚠ %s${NC}\n" "$*"; }
error()   { printf "${RED}  ✖ %s${NC}\n" "$*" >&2; }
die()     { error "$@"; exit 1; }

# ---------------------------------------------------------------------------
# Resolve the main (non-worktree) repository root from a worktree directory.
#
# A worktree has a plain-text .git file that looks like:
#   gitdir: /path/to/main-repo/.git/worktrees/<name>
#
# The main worktree is the repo root containing that .git directory.
# ---------------------------------------------------------------------------
resolve_main_worktree() {
    local worktree_dir="$1"
    local dot_git="$worktree_dir/.git"

    if [[ -d "$dot_git" ]]; then
        die "'$worktree_dir' is not a git worktree (has a real .git/ directory). This tool is for worktrees only."
    fi

    if [[ ! -f "$dot_git" ]]; then
        die "No .git file found in '$worktree_dir'. Not a git worktree."
    fi

    local gitdir
    gitdir="$(sed -n 's/^gitdir: //p' "$dot_git")"

    if [[ -z "$gitdir" ]]; then
        die "Could not parse gitdir from '$dot_git'."
    fi

    # gitdir: /path/to/main-repo/.git/worktrees/<name>
    # Main worktree: strip /.git/worktrees/<name>
    local main_worktree
    main_worktree="$(cd "$gitdir/../../.." && pwd)"

    if [[ ! -d "$main_worktree/.git" ]]; then
        die "Resolved main worktree '$main_worktree' does not have a .git/ directory."
    fi

    echo "$main_worktree"
}

# ---------------------------------------------------------------------------
# Derive a DDEV-safe project name from a directory name.
# DDEV requires lowercase, dots and hyphens only, starting with a letter.
# ---------------------------------------------------------------------------
sanitize_project_name() {
    local name
    name="$(basename "$1")"
    name="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
    name="$(echo "$name" | sed 's/[^a-z0-9.-]/-/g')"
    name="$(echo "$name" | sed 's/^[-.]*//' | sed 's/[-.]*$//')"
    # Ensure it starts with a letter (prefix 'pw-' guarantees this)
    echo "pw-${name}"
}

# ---------------------------------------------------------------------------
# Resolve WORKTREE_PATH argument (defaults to cwd).
# ---------------------------------------------------------------------------
resolve_worktree_path() {
    if [[ -n "${1:-}" ]]; then
        cd "$1" 2>/dev/null || die "Directory '$1' does not exist."
    fi
    pwd
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

# --- setup: one-shot init + start + import-db --------------------------------
#
# The goal is to go from a bare worktree to a fully working DDEV environment
# with a populated database in a single command.
# ---------------------------------------------------------------------------
cmd_setup() {
    local worktree_dir
    worktree_dir="$(resolve_worktree_path "${1:-}")"
    local project_name
    project_name="$(sanitize_project_name "$worktree_dir")"

    echo ""
    printf "${CYAN}${BOLD}  DDEV Worktree Setup${NC}\n"
    printf "  %s\n\n" "$worktree_dir"

    # --- Pre-flight: check that the main project's DDEV is running ------------
    local main_worktree
    main_worktree="$(resolve_main_worktree "$worktree_dir")"

    local main_project_name
    if [[ -f "$main_worktree/.ddev/config.yaml" ]]; then
        main_project_name="$(grep -E '^name:' "$main_worktree/.ddev/config.yaml" | head -1 | awk '{print $2}')"
    fi
    if [[ -z "$main_project_name" ]]; then
        die "Could not determine main project's DDEV name."
    fi

    info "Checking main project '$main_project_name' is running..."
    if ! ddev describe "$main_project_name" &>/dev/null; then
        info "Main project is stopped — starting it now..."
        (cd "$main_worktree" && ddev start)
        ok "Main project started."
    else
        ok "Main project is running."
    fi

    # --- Step 1: init ----------------------------------------------------------
    echo ""
    printf "${BOLD}  [1/3] Initializing DDEV config...${NC}\n"
    cmd_init "$worktree_dir"

    # --- Step 2: start ---------------------------------------------------------
    echo ""
    printf "${BOLD}  [2/3] Starting containers...${NC}\n"
    cmd_start "$worktree_dir"

    # --- Step 3: import-db -----------------------------------------------------
    echo ""
    printf "${BOLD}  [3/3] Importing database from main project...${NC}\n"
    cmd_import_db "$worktree_dir"

    # --- Done ------------------------------------------------------------------
    echo ""
    printf "${GREEN}${BOLD}  Setup complete!${NC}\n"
    printf "  Project: ${BOLD}%s${NC}\n" "$project_name"
    printf "  URL:     ${BOLD}https://%s.ddev.site${NC}\n" "$project_name"
    echo ""
    ok "You can start working now."
}

cmd_init() {
    local worktree_dir
    worktree_dir="$(resolve_worktree_path "${1:-}")"

    info "Initializing DDEV for worktree: $worktree_dir"

    # 1. Resolve the main worktree
    local main_worktree
    main_worktree="$(resolve_main_worktree "$worktree_dir")"
    ok "Main worktree: $main_worktree"

    # 2. Verify main .ddev/ exists
    local main_ddev="$main_worktree/.ddev"
    if [[ ! -d "$main_ddev" ]]; then
        die "Main worktree has no .ddev/ directory at '$main_ddev'. Set up DDEV there first."
    fi

    # 3. Create .ddev/ in the worktree
    local worktree_ddev="$worktree_dir/.ddev"
    if [[ -d "$worktree_ddev" ]]; then
        warn ".ddev/ already exists in worktree — updating symlinks."
    else
        mkdir -p "$worktree_ddev"
        ok "Created $worktree_ddev"
    fi

    # 4. Symlink shared config files from main .ddev/
    local files_to_link=("config.yaml")
    local optional_files=("apache-site.conf" "nginx-site.conf")

    for f in "${files_to_link[@]}"; do
        if [[ -e "$main_ddev/$f" ]]; then
            ln -sfn "$main_ddev/$f" "$worktree_ddev/$f"
            ok "Linked $f"
        else
            warn "Expected $f in main .ddev/ — not found, skipping."
        fi
    done

    for f in "${optional_files[@]}"; do
        if [[ -e "$main_ddev/$f" ]]; then
            ln -sfn "$main_ddev/$f" "$worktree_ddev/$f"
            ok "Linked $f"
        fi
    done

    # Symlink php/ directory if it exists
    if [[ -d "$main_ddev/php" ]]; then
        ln -sfn "$main_ddev/php" "$worktree_ddev/php"
        ok "Linked php/ directory"
    fi

    # 5. Generate config.local.yaml
    local project_name
    project_name="$(sanitize_project_name "$worktree_dir")"

    cat > "$worktree_ddev/config.local.yaml" <<EOF
# ddev-silent-no-warn
# ddev-worktree: auto-generated — do not edit manually
name: ${project_name}
EOF

    ok "Generated config.local.yaml (project: ${project_name})"

    # 6. Generate site/config-dev.php for the worktree
    local config_dev="$worktree_dir/site/config-dev.php"
    local ddev_url="${project_name}.ddev.site"

    if [[ -f "$config_dev" ]]; then
        # Update httpHosts to include the worktree's DDEV URL
        if grep -q "httpHosts" "$config_dev"; then
            local old_hosts
            old_hosts="$(grep -oP "httpHosts\s*=\s*array\(\K[^)]+" "$config_dev" || true)"
            if [[ -n "$old_hosts" ]]; then
                # Prepend the new URL to the existing hosts list
                sed -i "s|httpHosts\s*=\s*array([^)]*)|httpHosts = array('${ddev_url}', ${old_hosts})|" "$config_dev" 2>/dev/null || true
            fi
        fi
        ok "Existing site/config-dev.php found (verified httpHosts)."
    elif [[ -f "$main_worktree/site/config-dev.php" ]]; then
        # Copy from main worktree and adapt httpHosts
        cp "$main_worktree/site/config-dev.php" "$config_dev"
        # Replace httpHosts with the worktree's URL
        if grep -q "httpHosts" "$config_dev"; then
            sed -i "s|httpHosts\s*=\s*array([^)]*)|httpHosts = array('${ddev_url}')|" "$config_dev"
        fi
        ok "Created site/config-dev.php with URL ${ddev_url}"
    else
        warn "No site/config-dev.php template found in main worktree."
        warn "You will need to create one with DDEV database credentials (db/db/db)."
    fi

    # 7. Success
    echo ""
    printf "${CYAN}${BOLD}  DDEV worktree initialized!${NC}\n"
    printf "  Project name: ${BOLD}%s${NC}\n" "$project_name"
    printf "  URL: ${BOLD}https://%s.ddev.site${NC}\n" "$project_name"
    echo ""
    info "Run '$(basename "$0") start $worktree_dir' to start the environment."
}

cmd_start() {
    local worktree_dir
    worktree_dir="$(resolve_worktree_path "${1:-}")"

    if [[ ! -d "$worktree_dir/.ddev" ]]; then
        die "No .ddev/ directory in '$worktree_dir'. Run '$(basename "$0") init' first."
    fi

    info "Starting DDEV in $worktree_dir"
    (cd "$worktree_dir" && ddev start)
    ok "DDEV started for $(sanitize_project_name "$worktree_dir")"
}

cmd_stop() {
    local worktree_dir
    worktree_dir="$(resolve_worktree_path "${1:-}")"

    if [[ ! -d "$worktree_dir/.ddev" ]]; then
        die "No .ddev/ directory in '$worktree_dir'."
    fi

    info "Stopping DDEV in $worktree_dir"
    (cd "$worktree_dir" && ddev stop)
    ok "DDEV stopped."
}

cmd_import_db() {
    local worktree_dir
    worktree_dir="$(resolve_worktree_path "${1:-}")"

    if [[ ! -d "$worktree_dir/.ddev" ]]; then
        die "No .ddev/ directory in '$worktree_dir'. Run '$(basename "$0") init' first."
    fi

    local main_worktree
    main_worktree="$(resolve_main_worktree "$worktree_dir")"

    # Read the main project's DDEV project name from its config
    local main_project_name
    if [[ -f "$main_worktree/.ddev/config.yaml" ]]; then
        main_project_name="$(grep -E '^name:' "$main_worktree/.ddev/config.yaml" | head -1 | awk '{print $2}')"
    fi

    if [[ -z "$main_project_name" ]]; then
        die "Could not determine main project's DDEV name from $main_worktree/.ddev/config.yaml"
    fi

    local tmpfile="/tmp/ddev-worktree-db-${main_project_name}-$$.sql.gz"

    info "Exporting database from main project '$main_project_name'..."
    ddev export-db "$main_project_name" --file="$tmpfile"
    ok "Database exported to $tmpfile"

    info "Importing database into worktree..."
    (cd "$worktree_dir" && ddev import-db --file="$tmpfile")
    ok "Database imported."

    rm -f "$tmpfile"
    ok "Cleaned up temporary file."
}

cmd_snapshot_db() {
    local worktree_dir
    worktree_dir="$(resolve_worktree_path "${1:-}")"

    if [[ ! -d "$worktree_dir/.ddev" ]]; then
        die "No .ddev/ directory in '$worktree_dir'."
    fi

    local snapshot_name
    snapshot_name="worktree-snapshot-$(date +%Y%m%d-%H%M%S)"

    info "Creating DDEV snapshot '$snapshot_name'..."
    (cd "$worktree_dir" && ddev snapshot --name="$snapshot_name")
    ok "Snapshot created: $snapshot_name"
}

cmd_destroy() {
    local worktree_dir
    worktree_dir="$(resolve_worktree_path "${1:-}")"

    if [[ ! -d "$worktree_dir/.ddev" ]]; then
        die "No .ddev/ directory in '$worktree_dir'."
    fi

    local project_name
    project_name="$(sanitize_project_name "$worktree_dir")"

    echo ""
    printf "${RED}${BOLD}  ⚠  This will destroy the DDEV project '${project_name}'${NC}\n"
    printf "  and remove ${worktree_dir}/.ddev/\n\n"
    read -rp "  Are you sure? [y/N] " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        info "Aborted."
        return
    fi

    info "Stopping and removing DDEV project..."
    (cd "$worktree_dir" && ddev delete --omit-snapshot --yes 2>/dev/null || true)

    info "Removing .ddev/ directory..."
    rm -rf "$worktree_dir/.ddev"
    ok "Destroyed DDEV environment for '$project_name'."
}

cmd_status() {
    info "Scanning for worktree DDEV environments..."

    # Walk through git worktrees listed by `git worktree list`
    local found=0

    while IFS= read -r wt_line; do
        local wt_path
        wt_path="$(echo "$wt_line" | awk '{print $1}')"

        # Skip the main worktree (it has .git/ as a directory)
        if [[ -d "$wt_path/.git" ]]; then
            continue
        fi

        if [[ -f "$wt_path/.ddev/config.local.yaml" ]] && \
           grep -q "ddev-worktree: auto-generated" "$wt_path/.ddev/config.local.yaml" 2>/dev/null; then

            local project_name
            project_name="$(grep '^name:' "$wt_path/.ddev/config.local.yaml" | awk '{print $2}')"

            local status="stopped"
            if ddev describe "$project_name" &>/dev/null; then
                status="running"
            fi

            if [[ "$status" == "running" ]]; then
                printf "  ${GREEN}✔${NC} %-40s ${BOLD}%s${NC}  %s\n" "$wt_path" "$project_name" "https://${project_name}.ddev.site"
            else
                printf "  ${RED}✔${NC} %-40s %s  %s\n" "$wt_path" "$project_name" "(stopped)"
            fi
            found=$((found + 1))
        fi
    done < <(git worktree list --porcelain 2>/dev/null | grep "^worktree " | sed 's/^worktree //')

    if [[ $found -eq 0 ]]; then
        warn "No worktree DDEV environments found."
    fi
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
    cat <<EOF
${BOLD}$(basename "$0")${NC} — Manage DDEV environments for git worktrees

${BOLD}Usage:${NC}
  $(basename "$0") <command> [WORKTREE_PATH]

${BOLD}Commands:${NC}
  setup [PATH]        One-shot: init + start + import database from main project
  init [PATH]         Set up DDEV in a worktree (symlink config, generate config.local.yaml)
  start [PATH]        Start the worktree's DDEV project
  stop [PATH]         Stop the worktree's DDEV project
  import-db [PATH]    Import database from the main project's DDEV
  snapshot-db [PATH]  Create a DDEV snapshot of the worktree's database
  destroy [PATH]      Remove DDEV project and .ddev/ from the worktree
  status              List all worktree DDEV environments

${BOLD}Notes:${NC}
  WORKTREE_PATH defaults to the current working directory.
  Run from within a git worktree, or pass the path to one.

EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

command="$1"
shift

case "$command" in
    setup)       cmd_setup "$@" ;;
    init)        cmd_init "$@" ;;
    start)       cmd_start "$@" ;;
    stop)        cmd_stop "$@" ;;
    import-db)   cmd_import_db "$@" ;;
    snapshot-db) cmd_snapshot_db "$@" ;;
    destroy)     cmd_destroy "$@" ;;
    status)      cmd_status ;;
    -h|--help|help)
        usage
        exit 0
        ;;
    *)
        die "Unknown command: $command\nRun '$(basename "$0") --help' for usage."
        ;;
esac
