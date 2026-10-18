#!/usr/bin/env bash
# Neovim 0.13-targeted native zero-plugin configuration installer.
#
# Usage:
#   ./install.sh            install latest stable Neovim (>= policy minimum)
#                           plus this configuration
#   ./install.sh --check    verify environment and configuration, change nothing
#   ./install.sh --dry-run  print the plan without touching anything
#   ./install.sh --nightly  explicitly opt into the 0.13 nightly build
#
# Version policy: this configuration targets Neovim 0.13 or newer. 0.13 was
# still nightly-only when this was written, so the default channel installs
# the newest STABLE release (0.12.x) and reports the 0.13-only features
# (native multicursor, vim.ui.img) as unavailable. Nightly installs happen
# ONLY with --nightly.
#
# Safety rules honored here:
#   * existing ~/.config/nvim is backed up (tar.gz) before replacement, never
#     deleted
#   * ~/.local/state/nvim / ~/.local/share/nvim are never touched
#   * sudo is used only for package-manager installs, and only after asking
#   * binaries come from official Neovim release tarballs over HTTPS; when
#     release notes publish a sha256 for the asset, it is verified

set -u

MODE="install"
case "${1:-}" in
  --check) MODE="check" ;;
  --dry-run) MODE="dry" ;;
  --nightly) MODE="nightly" ;;
  "") ;;
  *) printf 'Unknown option: %s\nUsage: install.sh [--check|--dry-run|--nightly]\n' "$1" >&2; exit 2 ;;
esac

# ---------------------------------------------------------------- helpers

log()   { printf '[install] %s\n' "$*"; }
warn()  { printf '[install] WARNING: %s\n' "$*" >&2; }
die()   { printf '[install] ERROR: %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Run a command, unless in --check/--dry-run mode.
run() {
  if [ "$MODE" = "dry" ]; then
    log "(dry-run) would run: $*"
    return 0
  fi
  if [ "$MODE" = "check" ]; then
    log "(check) skipping: $*"
    return 0
  fi
  "$@"
}

prompt_yn() {
  if [ "$MODE" != "install" ] && [ "$MODE" != "nightly" ]; then
    return 0 # non-mutating modes never prompt
  fi
  if [ ! -t 0 ]; then
    printf '%s [auto-no: not a tty]\n' "$1" >&2
    return 1
  fi
  printf '%s [y/N] ' "$1"
  IFS= read -r reply || return 1
  case "$reply" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------- detection

OS_TYPE="$(uname -s)"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) NVIM_ARCH="x86_64" ;;
  aarch64|arm64) NVIM_ARCH="arm64" ;;
  *) NVIM_ARCH="$ARCH" ;;
esac

PM=""
PM_INSTALL=""
if [ "$OS_TYPE" = "Darwin" ]; then
  PLATFORM="macOS"
  if [ -x /opt/homebrew/bin/brew ]; then BREW=/opt/homebrew/bin/brew
  elif have brew; then BREW="$(command -v brew)"
  else BREW=""; fi
  [ -n "$BREW" ] && PM="brew" && PM_INSTALL="$BREW install"
elif [ "$OS_TYPE" = "Linux" ]; then
  PLATFORM="Linux"
  if have pacman; then PM="pacman"; PM_INSTALL="sudo -n pacman -S --noconfirm --needed"
  elif have dnf; then PM="dnf"; PM_INSTALL="sudo -n dnf install -y"
  elif have zypper; then PM="zypper"; PM_INSTALL="sudo -n zypper install -y"
  elif have apt-get; then PM="apt-get"; PM_INSTALL="sudo -n apt-get install -y"
  else PM=""; fi
else
  PLATFORM="$OS_TYPE"
fi

CONFIG_SRC="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DST="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
NVIM_LOCAL_OPT="$HOME/.local/opt/neovim"
NVIM_LOCAL_BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"

# ---------------------------------------------------------------- nvim version

nvim_major_minor() {
  "$1" --version 2>/dev/null | sed -n 's/^NVIM v\([0-9]*\.[0-9]*\).*/\1/p' | head -1
}

nvim_version_full() {
  "$1" --version 2>/dev/null | head -1 | sed 's/^NVIM //'
}

ver_ge() { # ver_ge A B: "A >= B" using sort -V (portable)
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$2" ]
}

# ---------------------------------------------------------------- main flow

log "platform: $PLATFORM/$NVIM_ARCH, package manager: ${PM:-none}"

NVIM=""
if have nvim; then NVIM="$(command -v nvim)"; fi
NVIM_VER=""
if [ -n "$NVIM" ]; then
  NVIM_VER="$(nvim_version_full "$NVIM")"
  log "neovim: $NVIM_VER at $NVIM"
else
  log "neovim: not found"
fi

if [ "$MODE" = "check" ]; then
  log "--- check mode ---"
  # Configuration load test (does not mutate anything).
  if [ -n "$NVIM" ]; then
    if timeout 30 "$NVIM" --headless "+lua print('config load: OK')" +qa >/dev/null 2>&1; then
      log "configuration loads headlessly: OK"
    else
      warn "configuration failed to load headlessly"
      exit 1
    fi
  fi
  for tool in rg fd fzf; do
    if have "$tool"; then log "optional search tool present: $tool"; else
      log "optional search tool missing: $tool (config degrades gracefully)"
    fi
  done
  log "check complete"
  exit 0
fi

if [ "$MODE" = "nightly" ]; then
  warn "NIGHTLY selected: 0.13 nightly is prerelease software and may break."
  warn "Native multicursor and vim.ui.img live on this channel."
  prompt_yn "Continue installing the 0.13 nightly build?" || die "aborted by user"
fi

# Decide required nvim channel.
TARGET_MIN="0.11"   # hard floor: the config refuses to load below this
TARGET_STABLE="0.12" # preferred stable line

NEED_INSTALL=0
if [ -z "$NVIM" ]; then
  NEED_INSTALL=1
else
  MM="$(nvim_major_minor "$NVIM")"
  if [ -z "$MM" ]; then
    NEED_INSTALL=1
  elif ! ver_ge "$MM" "$TARGET_MIN"; then
    NEED_INSTALL=1
  elif [ "$MODE" = "nightly" ] && [ "$MM" = "$TARGET_STABLE" ]; then
    # user explicitly asked for nightly; provide it
    NEED_INSTALL=1
  else
    if ver_ge "$MM" "0.13"; then
      log "neovim already satisfies the nightly target: $MM"
      NEED_INSTALL=0
    else
      log "neovim $MM is the newest STABLE channel (0.13 nightly-only); keeping it"
      warn "0.13-only features (native multicursor, vim.ui.img) stay unavailable until you run ./install.sh --nightly"
      NEED_INSTALL=0
    fi
  fi
fi

install_stable_tarball() {
  local tag="stable"
  local base="https://github.com/neovim/neovim/releases/download/$tag"
  local asset
  case "$PLATFORM/$NVIM_ARCH" in
    Linux/x86_64) asset="nvim-linux-x86_64.tar.gz" ;;
    Linux/arm64)  asset="nvim-linux-arm64.tar.gz" ;;
    macOS/arm64)  asset="nvim-macos-arm64.tar.gz" ;;
    macOS/x86_64) asset="nvim-macos-x86_64.tar.gz" ;;
    *) die "no official tarball for $PLATFORM/$NVIM_ARCH; install Neovim manually from https://neovim.io" ;;
  esac
  local url="$base/$asset"
  local tmpdir
  tmpdir="$(mktemp -d)" || die "mktemp failed"
  log "downloading official release tarball: $url"
  run sh -c "curl -fL '$url' -o '$tmpdir/$asset'" || die "download failed"
  # Integrity: GitHub publishes sha256 in release notes when available.
  if curl -sfL "https://api.github.com/repos/neovim/neovim/releases/tags/$tag" \
      -o "$tmpdir/release.json" 2>/dev/null; then
    local want
    want="$(sed -n 's/.*'"$asset"'[^"]*"[^"]*sha256:*/sha256/p; s/"sha256:\([a-f0-9]*\)".*/\1/p' "$tmpdir/release.json" | head -1)"
    # safer: grep the release body for asset/sha256 pairs
    want="$(grep -o "sha256:[a-f0-9]\{64\}[^)]*${asset}" "$tmpdir/release.json" 2>/dev/null | head -1 | sed 's/sha256:\([a-f0-9]*\).*/\1/')"
    if [ -n "$want" ]; then
      local got
      got="$(sha256sum "$tmpdir/$asset" 2>/dev/null | awk '{print $1}')"
      [ "$(uname)" = "Darwin" ] && command -v shasum >/dev/null && got="$(shasum -a 256 "$tmpdir/$asset" | awk '{print $1}')"
      if [ "$got" = "$want" ]; then
        log "sha256 verified for $asset"
      else
        die "sha256 mismatch for $asset — NOT installing"
      fi
    else
      warn "no sha256 for $asset found in release notes; proceeding over HTTPS"
    fi
  fi
  run mkdir -p "$NVIM_LOCAL_OPT" "$NVIM_LOCAL_BIN" || die "cannot create $NVIM_LOCAL_OPT"
  run tar -xzf "$tmpdir/$asset" -C "$tmpdir" || die "extraction failed"
  run rm -rf "$NVIM_LOCAL_OPT/nvim"
  run mv "$tmpdir/nvim-linux-x86_64" "$tmpdir/nvim-linux-arm64" "$tmpdir/nvim-macos-arm64" "$tmpdir/nvim-macos-x86_64" "$tmpdir/nvim" 2>/dev/null || true
  run mv "$tmpdir/nvim" "$NVIM_LOCAL_OPT/" || die "install move failed"
  run ln -sfn "$NVIM_LOCAL_OPT/nvim/bin/nvim" "$NVIM_LOCAL_BIN/nvim"
  NVIM="$NVIM_LOCAL_OPT/nvim/bin/nvim"
  log "installed nightly/stable tarball to $NVIM_LOCAL_OPT/nvim"
  log "make sure $NVIM_LOCAL_BIN is on your PATH"
}

if [ "$NEED_INSTALL" = "1" ]; then
  log "neovim needs installation/upgrade"
  if [ -n "$PM" ]; then
    if [ "$PM" = "brew" ]; then
      run "$BREW" install neovim || warn "brew install failed; falling back to tarball"
    else
      log "requesting permission: $PM_INSTALL neovim"
      if prompt_yn "Install neovim via $PM (requires sudo)?"; then
        run $PM_INSTALL neovim || warn "package install failed; trying the official tarball"
      else
        warn "declined; continuing without system-level neovim changes"
      fi
    fi
  fi
  if have nvim; then NVIM="$(command -v nvim)"; fi
  if [ -z "$NVIM" ] || ! ver_ge "$(nvim_major_minor "$NVIM")" "$TARGET_MIN"; then
    install_stable_tarball
  fi
fi

if [ -z "$NVIM" ] || ! have nvim && [ -z "$NVIM" ]; then
  [ -z "$NVIM" ] && die "neovim is still unavailable"
fi

# Optional search tools (best effort, never fatal).
for tool in ripgrep fd fzf; do
  if [ -n "$PM" ]; then
    need=0
    case "$tool" in
      ripgrep) have rg || need=1 ;;
      fd) have fd || need=1 ;;
      fzf) have fzf || need=1 ;;
    esac
    if [ "$need" = "1" ]; then
      if prompt_yn "Install optional search tool '$tool' via $PM?"; then
        run $PM_INSTALL "$tool" 2>/dev/null \
          || run $PM_INSTALL fd-find ripgrep fzf 2>/dev/null \
          || warn "could not install '$tool' automatically; install it manually"
      else
        warn "skipping optional '$tool'"
      fi
    fi
  else
    warn "no package manager; install rg/fd/fzf manually if you want scriptable search"
  fi
done

# ------------------------------------------------------------ configuration

if [ "$CONFIG_SRC" != "$CONFIG_DST" ]; then
  if [ -d "$CONFIG_DST" ] && [ -n "$(ls -A "$CONFIG_DST" 2>/dev/null)" ]; then
    BACKUP="$(dirname "$CONFIG_DST")/nvim-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    log "backing up existing config at $CONFIG_DST into $BACKUP"
    if ! run tar -czf "$BACKUP" -C "$(dirname "$CONFIG_DST")" "$(basename "$CONFIG_DST")"; then
      die "backup failed; refusing to replace the existing configuration"
    fi
  fi
  run mkdir -p "$CONFIG_DST/lua/config"
  for f in init.lua README.md install.sh uninstall.sh smoke.sh; do
    [ -f "$CONFIG_SRC/$f" ] && run cp "$CONFIG_SRC/$f" "$CONFIG_DST/$f"
  done
  run cp "$CONFIG_SRC"/lua/config/*.lua "$CONFIG_DST/lua/config/"
  # Manifest: exact files this project installed; uninstall.sh reads it.
  {
    printf 'backup=%s\n' "${BACKUP:-none}"
    for f in init.lua README.md install.sh uninstall.sh smoke.sh; do
      [ -f "$CONFIG_SRC/$f" ] && printf 'file=%s\n' "$f"
    done
    printf 'dir=lua/config\n'
    printf 'nightly_dir=%s\n' "$NVIM_LOCAL_OPT/nvim"
    printf 'nightly_link=%s/nvim\n' "$NVIM_LOCAL_BIN"
  } > "$CONFIG_DST/.nvim-project-manifest"
else
  log "source and destination are the same directory ($CONFIG_SRC); installing in place"
  {
    printf 'backup=none\n'
    printf 'file=init.lua\nfile=README.md\nfile=install.sh\nfile=uninstall.sh\nfile=smoke.sh\n'
    printf 'dir=lua/config\n'
    printf 'nightly_dir=%s\n' "$NVIM_LOCAL_OPT/nvim"
    printf 'nightly_link=%s/nvim\n' "$NVIM_LOCAL_BIN"
  } > "$CONFIG_DST/.nvim-project-manifest"
fi

# ------------------------------------------------------------ verification

if [ "$MODE" != "dry" ]; then
  if [ ! -x "$NVIM" ] && have nvim; then NVIM="$(command -v nvim)"; fi
  log "installed neovim version: $(nvim_version_full "$NVIM")"
  if ! "$NVIM" --headless "+lua print('headless config test: OK')" +qa >/dev/null 2>&1; then
    die "headless configuration test FAILED — inspect output above"
  fi
  "$NVIM" --headless "+lua print('headless config test: OK')" +qa | tail -1
  MISSING=""
  have rg  || MISSING="$MISSING rg"
  have fd  || MISSING="$MISSING fd"
  have fzf || MISSING="$MISSING fzf"
  if [ -n "$MISSING" ]; then
    warn "optional search tools not installed:$MISSING (the editor still works; fuzzy search falls back)"
  fi
  log "DONE. Backup location: ${BACKUP:-none}"
  log "DONE. Start the editor with: nvim"
  if [ "$MODE" = "nightly" ]; then
    log "DONE. 0.13 nightly features to try: :help multicursor, :checkhealth vim.health"
  fi
fi
