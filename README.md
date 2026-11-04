![icon](./icons/icon.svg)

# Annal

[![License](https://img.shields.io/github/license/ahaooahaz/Annal)](https://raw.githubusercontent.com/ahaooahaz/Annal/master/LICENSE)

Synchronize develop environment, reference samples, built-in utils and configuration to build develop environment quickly.

## Configuration management

Requires GNU Make, Bash 3.2+ and Git. `make` defaults to `install` and detects
Linux/macOS automatically. Only directories containing a Makefile participate;
macOS modules may alias shared Linux modules through symlinks.

```sh
make install                         # install all modules for this platform
make TARGETS="git shell kitty" install
make -C dotutils/linux/tmux install  # operate on just one module
make uninstall                       # move installed links to backups
make prune                           # permanently delete managed backups
make upgrade                         # pull Annal and every nested Git repo
```

### Lifecycle

- **install** downloads missing declared plugins, creates parent directories,
  backs up existing destinations and creates absolute symlinks. A link already
  pointing at the correct source is left alone. Missing sources fail before
  any configuration destinations in that module are moved.
- **uninstall** moves only links pointing at this project's declared sources
  to `<destination>.backup.YYYYMMDDhhmmss`. Unrelated files and links are left
  alone. Old backups and plugin repositories are preserved. Repeated backups
  within the same second get numeric suffixes instead of overwriting one
  another.
- **prune** deletes all `<destination>.backup.*` files, directories and links
  for the selected modules, including registered legacy backup paths. It does
  not follow backup symlinks, delete active configurations or scan the whole
  HOME for unrelated backups. Pruning is irreversible; it does not restore
  earlier configurations.
- **upgrade** runs `git pull --ff-only`: at the project root it updates Annal
  first, then discovers every nested Git repository across all platforms,
  including undeclared plugins, nested plugins, submodules and worktrees.
  Directory symlinks are not followed, so macOS aliases do not cause duplicate
  pulls. A module's `upgrade` only scans that module, not its enclosing Annal
  repository. Missing plugins are downloaded by `install`, not `upgrade`.
  Failed pulls do not prevent remaining repositories from being attempted;
  the final exit status still reports failure. There is no automatic reset,
  stash, rebase or merge: local conflicts, missing upstreams or diverged
  histories must be resolved manually.

`TARGETS` selects modules for install/uninstall/prune. Root `upgrade` always
scans the entire project regardless of `TARGETS` or platform. Lifecycle
operations are serialized, including with `make -j`.

Paths honor `HOME`, `XDG_CONFIG_HOME` (default: `~/.config`) and
`XDG_DATA_HOME` (default: `~/.local/share`). Override platform detection with
`PLATFORM=linux` or `PLATFORM=darwin`.

Shell startup/logout files are symlinks too. Existing `.bashrc`/`.zshrc`
contents are preserved as backups, not merged. `.profile` and `.zprofile`
are left untouched; backups created by older installers can still be pruned.
Git's `.gitconfig.d/user.personal` and `user.work` are created only when
missing and remain user-owned, outside uninstall/prune.

### Adding a module

Declare source/destination pairs and optional GitHub plugins, then include
`mk/common.mk`; there is no need to duplicate lifecycle recipes:

```make
PLUGINS := owner/repository
CONFIG_LINKS = "$(MODULE_DIR)/config" "$(XDG_CONFIG_HOME)/example"
include $(dir $(realpath $(lastword $(MAKEFILE_LIST))))../../../mk/common.mk
```

`MODULE_DIR` is the module's physical directory. `CONFIG_LINKS` is a
shell-quoted list of pairs, expanded after loading the common Makefile.
`PLUGINS` repositories are cloned to `$(MODULE_DIR)/plugins/<repo-name>`.
Optional `EXTRA_FILES` declares user-owned files to initialize without
replacing them; `EXTRA_BACKUPS` declares target paths with legacy backups to
prune. Both lists should also be shell-quoted.

Shared implementation: `mk/common.mk`, `mk/platform.mk` and `mk/dotutils.sh`.
Run `make test` for offline integration tests using temporary HOME/config
paths, fake plugin downloads and real local Git remotes; no personal configs
or online repositories are changed. `make format` requires `shfmt`.

### [MIT LICENSE](LICENSE)
