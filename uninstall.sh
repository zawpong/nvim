#!/usr/bin/env bash
# Uninstaller for the native zero-plugin Neovim configuration.
#
# Removes ONLY files registered by install.sh in the project manifest.
# Never deletes ~/.local/state/nvim, ~/.local/share/nvim, backups, or any
# unrelated configuration. Restoring a backup is always documented and
# manual.

set -u

CONFIG_DST="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
MANIFEST="$CONFIG_DST/.nvim-project-manifest"

log()  { printf '[uninstall] %s\n' "$*"; }
warn() { printf '[uninstall] WARNING: %s\n' "$*" >&2; }
die()  { printf '[uninstall] ERROR: %s\n' "$*" >&2; exit 1; }

prompt_yn() {
  if [ ! -t 0 ]; then
    printf '%s [auto-NO: not a tty; rerun interactively to confirm]\n' "$1" >&2
    return 1
  fi
  printf '%s [y/N] ' "$1"
  IFS= read -r reply || return 1
  case "$reply" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

if [ "$#" != "0" ]; then
  die "uninstall.sh takes no arguments"
fi

if [ ! -d "$CONFIG_DST" ]; then
  log "nothing to uninstall: $CONFIG_DST does not exist"
  exit 0
fi

log "This uninstaller will remove, for the Neovim configuration installed by"
log "this project ONLY:"
if [ -f "$MANIFEST" ]; then
  log "  files listed in $MANIFEST:"
  grep -E '^(file|dir)=' "$MANIFEST" | sed 's/^/    /'
else
  log "  (no manifest found; a legacy install may be present)"
fi
log "It will NOT touch:"
log "  * backups (tar.gz files next to ~/.config/nvim)"
log "  * ~/.local/state/nvim, ~/.local/share/nvim"
log "  * any other dotfile or project"

prompt_yn "Proceed with uninstalling these files?" || die "aborted by user"

restore_backups() {
  log "backups created by install.sh (restore by hand if wanted):"
  ls -1t "$(dirname "$CONFIG_DST")"/nvim-backup-*.tar.gz 2>/dev/null | head -20 | while IFS= read -r b; do
    log "  $b"
  done
}

restore_backups

# Remove modules retired in later UI revisions, even if they predate the
# current manifest.
for obsolete in contextline.lua winbar.lua context.lua gitline.lua context_line.lua; do
  target="$CONFIG_DST/lua/config/$obsolete"
  if [ -f "$target" ]; then
    rm -f "$target" && log "removed obsolete module: $obsolete"
  fi
done

# Identify manifest-driven files.
if [ -f "$MANIFEST" ]; then
  while IFS= read -r line; do
    case "$line" in
      file=*)
        f="${line#file=}"
        target="$CONFIG_DST/$f"
        if [ -f "$target" ]; then
          rm -f "$target" && log "removed file: $f"
        fi
        ;;
      dir=*)
        d="${line#dir=}"
        target="$CONFIG_DST/$d"
        if [ -d "$target" ]; then
          rmdir "$target" 2>/dev/null && log "removed empty dir: $d" \
            || log "left dir (not empty): $d"
        fi
        ;;
      nightly_dir=*)
        d="${line#nightly_dir=}"
        if [ -d "$d" ]; then
          rm -rf "$d" && log "removed nightly install dir: $d"
        fi
        ;;
      nightly_link=*)
        l="${line#nightly_link=}"
        if [ -L "$l" ]; then
          rm -f "$l" && log "removed nightly symlink: $l"
        fi
        ;;
    esac
  done < "$MANIFEST"
  rm -f "$MANIFEST" && log "manifest removed"
else
  warn "no manifest found; NOT deleting anything (safety rule: only manifest-registered files may be removed)"
fi

# Remove now-empty lua directories after manifest-driven file removal.
for d in lua/config lua; do
  target="$CONFIG_DST/$d"
  if [ -d "$target" ] && [ -z "$(ls -A "$target" 2>/dev/null)" ]; then
    rmdir "$target" 2>/dev/null && log "removed empty dir: $d"
  fi
done

log "uninstall complete. Restore a backup with, for example:"
log "  tar -xzf '$(dirname "$CONFIG_DST")'/nvim-backup-<timestamp>.tar.gz -C '$(dirname "$CONFIG_DST")'"
log "(the newest backup is not automatically the right one; pick the timestamp you trust)"
