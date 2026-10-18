# Neovim 0.13-targeted native configuration — zero plugins

A production-quality Neovim configuration with a strict native-first
philosophy: **no third-party plugins**, no plugin manager, no network access
at startup, minified surface area of features that are used daily.

Everything is built on verified native APIs. Neovim 0.13-only features are
detected at runtime and never fabricated when running on stable.

```text
~/.config/nvim/
├── init.lua          entry point, deterministic module load order
├── README.md         this file
├── install.sh        cross-platform installer (--check|--dry-run|--nightly)
├── uninstall.sh      manifest-driven uninstaller with confirmation
├── smoke.sh          automated headless tests
└── lua/config/
    ├── options.lua    editor options, persistent state dirs, clipboards
    ├── keymaps.lua    general keybindings
    ├── autocmds.lua   editor events (yank highlight, cursor restore, …)
    ├── diagnostics.lua diagnostic display and jump API
    ├── statusline.lua minimal native statusline
    ├── search.lua     <leader>ff/fg/fb/fh (fd/rg/fzf, no plugins)
    ├── lsp.lua        native LSP definitions, attachment, format-on-save
    ├── treesitter.lua parser detection and syntax fallback
    ├── multicursor.lua native multicursor reporting (0.13+)
    ├── images.lua     vim.ui.img capability and :ImageShow (0.13+)
    └── utils.lua      shared helpers (root detection, executables)
```

## Supported Neovim versions

| Channel | Status | Supported by this config |
|---|---|---|
| 0.13 nightly | prerelease (upstream development as of writing) | yes, via `./install.sh --nightly` |
| 0.12.x stable | current stable | yes, default |
| < 0.11 | unsupported | no |

Neovim 0.13 was still nightly-only when this configuration was written, so:

* the default install uses the **newest stable** release (0.12.x),
* features that only exist on 0.13 (**native multicursor**, **`vim.ui.img`**)
  are guarded at runtime and reported honestly; they are never emulated in
  Lua, and
* `./install.sh --nightly` is the only way this installer puts a nightly on
  your system. It warns and asks before touching anything.

Verify your build with `nvim --version`. The configuration floor is checked
in `install.sh --check`.

## Supported operating systems

`install.sh` is written for:

* Arch Linux and derivatives (pacman)
* Debian/Ubuntu-based Linux (apt)
* Fedora-based Linux (dnf)
* openSUSE (zypper)
* macOS with Homebrew

Systems without any of those get a documented manual path (official Neovim
release tarballs are still used, without sudo, into `~/.local/opt/neovim`
plus a `~/.local/bin/nvim` symlink).

## Installation

```sh
./install.sh          # stable channel + patch this config into ~/.config/nvim
./install.sh --check  # verify environment and configuration; change nothing
./install.sh --dry-run
./install.sh --nightly # explicit 0.13 nightly (warns, asks, verifies tarball)
```

The installer:

1. detects OS, architecture and available package managers,
2. keeps your already-adequate Neovim when present (never downgrades),
3. installs Neovim from the official source otherwise (system package when
   available, otherwise the official release tarball with sha256 kept from
   upstream release notes when published),
4. offers (optional, never silent) installs for the search tools
   `ripgrep`, `fd`, `fzf` — a decline or failure is not fatal,
5. backs up an existing `~/.config/nvim` to a timestamped tar.gz before
   replacing it, printing the exact path, and
6. runs a headless config test and reports missing optional tools.

Running it repeatedly is safe.

## Backup and rollback

* The pre-replacement backup path is printed by `install.sh` and also
  recorded in `~/.config/nvim/.nvim-project-manifest`.
* Restore with, e.g.:

  ```sh
  tar -xzf ~/.config/nvim-backup-YYYYmmdd-HHMMSS.tar.gz -C ~/.config/
  ```
* Do not assume the newest backup is the one you want — pick the timestamp
  you trust.
* `./uninstall.sh` removes only manifest-registered files, after explicit
  confirmation, and tells you which backups exist.

## Keybindings

Leader is **Space**. Highlights:

| Keys | Action |
|---|---|
| `<leader>ff` | fuzzy file search (fd; fallback rg --files; fallback walk) |
| `<leader>fg` | live ripgrep content search with preview |
| `<leader>fb` | buffer search |
| `<leader>fh` | help-topic search |
| `<leader>e` | netrw file explorer |
| `<leader>w` / `<leader>q` / `<leader>qa` | save / quit / quit all |
| `<leader>sv` / `<leader>sh` / `<leader>sc` | splits |
| `<leader>bn` / `<leader>bp` / `<leader>bd` / `<leader>bb` | buffers |
| `<leader>t` | terminal split (`<Esc><Esc>` returns to normal mode) |
| `<leader>dv` / `<leader>d` / `<leader>dl` | diagnostics toggle/floating/list |
| `[d` `]d` | previous/next diagnostic (native jump API) |
| `<leader>co` / `<leader>cc`, `<leader>lo` / `<leader>lc` | quickfix/location |
| `<leader>=` | LSP-backed format-on-demand (`vim.lsp.buf.format`, async) |
| `gd`, `gi`, `gr`, `gt`, `K` | LSP navigation (buffer-local once attached) |
| `<leader>rn`, `<leader>ca`, `<leader>ds`, `<leader>ws` | rename/action/symbols |
| `<leader>gs` / `<leader>gd` / `<leader>gD` / `<leader>gl` | git via terminal split |
| `<Esc>` | clear search highlight |

Search pickers (all four `<leader>f?` flows): type to fuzzy-filter
(`fzf --filter` when fzf is installed, otherwise the native `matchfuzzy`),
`Enter` accepts, `Esc` cancels, `Ctrl-J`/`Ctrl-K` (or Ctrl-N/P) move the
selection, Backspace edits the query (including UTF-8), `Tab` moves back.
`Up`/`Down` (and `Left`/`Right`, which are no-ops) also work: arrow keys are
decoded by `getcharstr()` into key codes and classified with `keytrans()`, so a
stray `<Up>` can no longer be misread as the `Esc` that cancels the picker.
The floats are force-repainted
(`redraw`) before the input loop and after every query change, because without
that some terminals (verified under tmux/xterm-256color) never paint the
two-float layout while `getcharstr()` blocks. The preview pane is clamped
inside the editor grid so narrow panes get a visible preview instead of an
off-screen one.

Known fuzzy-engine caveat: `fzf --filter` is a Go program that decodes its
input as UTF-8 and silently rewrites invalid byte sequences as U+FFFD. The
picker detects unfaithful output rows (not byte-identical to a real
candidate) and falls back to the byte-faithful native `matchfuzzy` engine, so
filenames that exist on disk survive end-to-end even when non-UTF-8.

Excludes (configurable via `lua/config/search.lua#M.opts`):
`.git/`, `node_modules/`, `build/`, `dist/`, `out/`, `target/`, `vendor/`,
`.cache/`, `.venv/`, `venv/`, `__pycache__/`. Hidden files are searched by
default; `.gitignore` is honored inside Git repositories (fd/rg behavior).

Search safety: tools are always passed as argument arrays — never shell
strings — so filenames with spaces, quotes, or dash-prefixed queries cannot
cause shell injection, and no temporary files or orphaned jobs are left
behind. `rg --vimgrep` rows are parsed as `path:line:col:text` with the
path allowed to contain extra colons.

## Native multicursor usage

Multicursor is **native editor functionality** in 0.13 — this config
installs no emulator and never remaps `Q`, `zq`, `gQ`, `q=` or `CTRL-L`.
On 0.12 stable those keys keep their classic meaning (`Q` = Ex-mode toggle
upstream; here unmapped, nothing emulated).

| Keys | Behavior (0.13+) |
|---|---|
| `Q` | place/toggle a cursor (prefix count adds or removes that many) |
| `zq{motion}` | place a cursor at every motion target (`zqgn`: each match) |
| `{Visual}` then `Q` | one cursor per selected line |
| `q=` | follow mode: replay your next keys at every cursor |
| `gQ` | restore the last cleared multicursor session |
| `]C` / `[C` | jump between cursors |
| `CTRL-L` | clear all cursors |

Terminal/display limits: cursors render via the kitty multi-cursor
protocol when the terminal supports it, otherwise through `hl-MCursor`
extmark highlighting. `:MulticursorInfo` reports the live count and this
key reference; on 0.12 it explains that the build cannot provide these
features and does not fake them.

Note: the config deliberately does NOT map `Ctrl-L` to window navigation on
0.13 builds (it would shadow multicursor clearing). On 0.12 the mapping
exists as usual.

## Image support and verified limitations

Neovim 0.13 upstream merges `vim.ui.img` as **EXPERIMENTAL** with these
constraints (verified against upstream docs and the implementation, not
blog posts):

* rendering goes through the **Kitty graphics protocol**,
* pixels must be embedded as `t=d` base64 bytes; path transmission (`t=f`)
  is not implemented, so files are read into memory before display,
* running inside **tmux** without passthrough is unsupported upstream,
* there is no healthcheck-free escape: `:checkhealth vim.health` reports
  image readiness,
* the API may change until the EXPERIMENTAL marker is dropped.

This config ships `:ImageShow [path]` (defaults to the file under the
cursor) and `:ImageClear`. Availability is decided at call time by the
upstream capability probe (`vim.ui.img._supported()`): the control flow never
guesses from `TERM` strings. PNG files are checked for the PNG signature,
capped at 12 MiB of embedded bytes, and placed at the cursor's screen
position; `:ImageClear` deletes the tracked placement id.

Verified behaviors in this environment (Neovim 0.13 nightly `0.13.0-dev-
1895`, kitty 0.48.2, Wayland/Hyprland):

* inside **kitty outside tmux**, `:ImageShow` renders real pixels — verified
  end-to-end with a uniquely-colored 220×90 PNG displayed at the cursor and
  measured from screen pixels (19800/19800 exact-color pixels after
  `:ImageShow`, 0 after `:ImageClear`),
* inside **tmux** on the same machine, the probe times out because upstream
  `vim.ui.img` implements no tmux passthrough; the command prints the exact
  reason (including `TERM`/`TERM_PROGRAM`) and shows nothing,
* on **0.12 stable**, the commands report the honest limitation.

If you run Kitty/Ghostty through tmux and want images anyway, that is an
upstream capability gap — not something this config papers over.

## Search usage and fallback behavior

| Missing tool | Behavior |
|---|---|
| `fzf` | warn once; native `matchfuzzy` engine takes over (same flow) |
| `fd` | `rg --files` takes over; if both are missing, a bounded Lua walk runs (max depth 6, noise directories respected) |
| `rg` | `<leader>ff` falls back as above; `<leader>fg` explains the missing dependency and suggests `:vim /pattern/j .` |

Nonzero exit codes, empty results, cancellations (`Esc`), and missing
executables are handled without raising errors. Search roots default to the
project root (found via `.git`/`go.mod`/`Cargo.toml`/`pyproject.toml`
markers), falling back to the CWD outside a Git repository.

## LSP servers (install separately)

| Language | Package (Arch) | notes |
|---|---|---|
| Lua | `lua-language-server` | LuaJIT runtime, `vim` recognized |
| Go | `gopls` | |
| Python | `basedpyright` (recommended) or `ruff` | first present wins |
| Rust | `rust-analyzer` | |
| C/C++ | `clangd` | `--background-index` |

The editor only ever *enables* servers whose executables are already on
PATH — nothing is downloaded at startup, and servers are entirely optional.
`:LspStatus` shows what is enabled and what got attached to the current
buffer. Format-on-save stays disabled unless you set `vim.g.format_on_save
= true` (then it runs once per buffer, per client, on `BufWritePre`).

## Performance

`nvim --headless +qa --startuptime` on this configuration:

| Phase | Measured |
|---|---|
| `init.lua` sourcing | ~8.7 ms |
| total headless start | ~15 ms |

Measure with the same command on your machine. No plugin manager is booted,
no network access happens, no parsers are downloaded, and no background jobs
are left running at rest.

## Testing

```sh
./smoke.sh             # 52 automated headless tests (verbatim results)
./smoke.sh --verbose   # also print raw Neovim output per test
./install.sh --check
```

Automated coverage: shell + Lua syntax, config boot, module loading, options,
user commands, keymap registration, real-keymap end-to-end flows
(`<leader>ff` opens the picker from async candidates and accepts the right
file; `<leader>fg` lands the cursor on the match line; `<leader>fb` opens and
`Esc` cancels), picker special-character filenames (brackets/quotes/colons
parse and open), the "No files found" empty-project message, non-UTF-8
candidate rendering and byte-faithful acceptance, image capability honesty
(inside tmux the message names the upstream no-passthrough limitation, on
stable the missing build), image file validation (missing/invalid PNG
rejected) and the placement-id lifecycle, fallback when fd/rg are missing,
LSP loading without servers, multicursor key honesty, and treesitter
fallbacks.

Manual UI checks (never automatable headlessly — do not trust anyone who
says otherwise):

1. start `nvim` inside Kitty and run `:ImageShow /path/to/picture.png` to
   confirm real pixel rendering (if a 0.13 nightly is installed),
2. run `:checkhealth vim.health`,
3. on a 0.13 build, test `Q`, `zqgn`, `q=`, `gQ`, `CTRL-L` by hand on real
   text, and
4. run interactive `<leader>ff`, `<leader>fg` in your real terminal.

## Troubleshooting

* **“`<leader>ff` says fd/rg is missing”** — install them
  (`pacman -S fd ripgrep`, `apt install fd-find ripgrep`, …). The editor
  remains fully usable meanwhile (walk fallback for files, vimgrep for
  content).
* **No LSP features** — check `:LspStatus`; the server executable is almost
  certainly not on PATH (nothing will be auto-installed for you).
* **Multicursor keys “do nothing”** — you are on the 0.12 stable channel;
  those features need a 0.13 build (`./install.sh --nightly`).
* **`vim.ui.img` unavailable / :ImageShow declines to show** — read the
  printed reason; common cases: stable channel, tmux passthrough, or a
  terminal that does not implement the kitty graphics protocol.
* **Clipboard not working** — install a provider (`wl-clipboard`, `pbcopy`
  on macOS, or `xclip`); without one, registers stay internal.
* **Backup needed?** the installer prints and records the exact tar.gz path
  it created; restore stickers printed in “Backup and rollback”.
