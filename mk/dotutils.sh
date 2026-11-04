#!/usr/bin/env bash
# Filesystem/Git operations shared by all modules. Compatible with Bash 3.2.
set -euo pipefail
shopt -s nullglob

exists() {
    [[ -e "$1" || -L "$1" ]]
}

is_link_to() {
    [[ -L "$2" ]] && { [[ "$(readlink "$2")" == "$1" ]] || [[ "$1" -ef "$2" ]]; }
}

backup() {
    local target=$1 destination base index=0
    exists "$target" || return 0
    base="$target.backup.$(date +%Y%m%d%H%M%S)"
    destination=$base
    # Repeated operations within one second must not overwrite earlier backups.
    while exists "$destination"; do
        index=$((index + 1))
        destination="$base.$index"
    done
    mv -- "$target" "$destination"
    printf 'Backup: %s -> %s\n' "$target" "$destination"
}

prune() {
    local target entry
    for target in "$@"; do
        for entry in "$target".backup.*; do
            # rm removes symlinks themselves, never their referenced configs.
            rm -rf -- "$entry"
            printf 'Pruned: %s\n' "$entry"
        done
    done
}

links() {
    local action=$1 source target index
    shift
    if (($# % 2 != 0)); then
        printf 'Expected source/destination pairs for %s\n' "$action" >&2
        return 1
    fi
    case "$action" in
    install)
        # Validate every source before moving any user configuration.
        for ((index = 1; index <= $#; index += 2)); do
            source=${!index}
            if [[ ! -e "$source" ]]; then
                printf 'Missing link source: %s\n' "$source" >&2
                return 1
            fi
        done
        ;;
    uninstall | prune) ;;
    *)
        printf 'Unknown link action: %s\n' "$action" >&2
        return 1
        ;;
    esac
    while (($#)); do
        source=$1 target=$2
        shift 2
        case "$action" in
        install)
            if is_link_to "$source" "$target"; then
                printf 'Already linked: %s\n' "$target"
                continue
            fi
            mkdir -p -- "$(dirname "$target")"
            backup "$target"
            ln -s -- "$source" "$target"
            printf 'Linked: %s -> %s\n' "$target" "$source"
            ;;
        uninstall)
            # Leave unrelated files/links alone, even if sources are missing.
            if is_link_to "$source" "$target"; then
                backup "$target"
            fi
            ;;
        prune) prune "$target" ;;
        esac
    done
}

init_files() {
    local file
    for file in "$@"; do
        if ! exists "$file"; then
            mkdir -p -- "$(dirname "$file")"
            touch -- "$file"
        fi
    done
}

clone_plugins() {
    local directory=$1 plugin destination
    shift
    for plugin in "$@"; do
        destination="$directory/${plugin##*/}"
        if exists "$destination"; then
            if [[ ! -d "$destination/.git" && ! -f "$destination/.git" ]]; then
                printf 'Plugin path is not a Git repository: %s\n' "$destination" >&2
                return 1
            fi
            printf 'Plugin already exists: %s\n' "$destination"
        else
            mkdir -p -- "$directory"
            git clone --depth 1 -- "https://github.com/$plugin.git" "$destination"
        fi
    done
}

pull_repository() {
    printf 'Upgrading: %s\n' "$1"
    # No reset, stash, rebase, or implicit merge of diverged histories.
    git -C "$1" pull --ff-only
}

upgrade() {
    local directory status=0
    directory=$(cd -- "$1" && pwd -P)
    # Update the scope's own repository before discovering nested repositories.
    if [[ -d "$directory/.git" || -f "$directory/.git" ]]; then
        if ! pull_repository "$directory"; then
            status=1
        fi
    fi
    # .git can be a directory or a file (worktrees/submodules). Do not follow
    # directory symlinks: aliases must not update the same repository twice.
    # Pipefail also reports scan errors; the loop aggregates all pull failures.
    if ! find "$directory" -name .git -prune -print0 | (
        result=0
        while IFS= read -r -d '' marker; do
            repository=${marker%/.git}
            [[ "$repository" != "$directory" ]] || continue
            if ! pull_repository "$repository"; then
                result=1
            fi
        done
        exit "$result"
    ); then
        status=1
    fi
    return "$status"
}

case "${1:-}" in
links)
    shift
    links "$@"
    ;;
prune)
    shift
    prune "$@"
    ;;
init-files)
    shift
    init_files "$@"
    ;;
clone)
    shift
    clone_plugins "$@"
    ;;
upgrade)
    shift
    upgrade "$@"
    ;;
*)
    printf 'Usage: %s {links ACTION SOURCE TARGET...|prune TARGET...|init-files FILE...|clone DIR REPO...|upgrade DIR}\n' "$0" >&2
    exit 1
    ;;
esac
