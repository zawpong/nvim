# Native Neovim Configuration (Zero Plugins)

A minimal, fast, native-first Neovim setup for Arch Linux. No third-party Neovim plugins.

## Supported version

- Neovim 0.12.5 (stable). Minimum: 0.11.0 (for `vim.lsp.config`/`vim.lsp.enable`).
- Older releases are not supported.

## Installation

Back up any existing config first:

```sh
if [ -d ~/.config/nvim ]; then
  cp -a ~/.config/nvim ~/.config/nvim.bak.$(date +%Y%m%d%H%M%S)
fi
```

This repository already lives at `~/.config/nvim`. To install from a clone:

```sh
git clone <repo-url> ~/.config/nvim
```

No plugin manager, no network access at startup.

## Required dependencies

- `neovim` (>= 0.11)
- `git`

## Optional dependencies

Arch (official repos unless noted):

```sh
sudo pacman -S ripgrep fd fzf wl-clipboard stylua
```

Language servers (install only what you need):

```sh
sudo pacman -S lua-language-server gopls rust-analyzer clangd
# Python
pip install --user basedpyright   # or pyright
# TypeScript/JavaScript (not installed by default)
npm i -g typescript-language-server
```

AI CLI tools (optional, any provider):

```sh
# examples
npm i -g @anthropic-ai/claude-code
```

## External parser cleanup (if upgrading from old plugin setups)

Stale parsers in `~/.local/share/nvim/site/parser` can shadow Neovim's bundled parsers and break Tree-sitter. If you see query errors, move that directory aside or remove only the offending `.so`.

## Usage

- Leader key: Space.
- See keybinding reference below.

### Keybindings

| Mapping | Action |
|---|---|
| `<leader>w` | Save |
| `<leader>q` | Quit window |
| `<leader>qa` | Quit all |
| `<leader>e` | Toggle file explorer (netrw) |
| `<leader>bn` / `<leader>bp` | Next/prev buffer |
| `<leader>bd` | Delete buffer (safe) |
| `<leader>sv` / `<leader>sh` | Vertical/horizontal split |
| `<C-h/j/k/l>` | Move between windows |
| `<leader>t` | Open terminal |
| `<Esc><Esc>` (terminal) | Terminal to normal mode |
| `[d` / `]d` | Prev/next diagnostic |
| `<leader>d` | Diagnostic float |
| `<leader>dl` | Diagnostics to location list |
| `[q` / `]q` | Prev/next quickfix |
| `[l` / `]l` | Prev/next location |
| `<leader>co` / `<leader>cc` | Open/close quickfix |
| `<leader>lo` / `<leader>lc` | Open/close location list |
| `<Esc>` | Clear search highlight |
| `<leader>f` | Format buffer (LSP) |
| `<leader>gs` / `gd` / `gD` / `gl` | Git status/diff/diff --check/log |
| `<leader>ai` | AI assistant terminal |
| `<leader>dv` | Toggle diagnostic virtual text |

LSP defaults (provided by Neovim): `gra` code action, `grr` references, `grn` rename, `gri` implementation, `grt` type definition, `gO` document symbols, `K` hover, `gd`/`gD` (custom), `CTRL-]` goto definition via tags.

### LSP

Servers are defined in `init.lua` (LSP section) and enabled only if their executable exists. To add a server, copy an example block and call `vim.lsp.enable()`.

Format-on-save is off by default; set `vim.g.format_on_save = true` near the top of `init.lua` to enable.

### Completion

Native LSP completion is enabled on attach with autotrigger. Use `CTRL-Y` to accept. `completeopt=menu,menuone,noselect,popup`.

### Search

Use `:grep`/`:vimgrep` and quickfix. Optional `rg`/`fd`/`fzf` improve speed but are not required.

```vim
:grep -R "pattern" .
:copen
```

### Git workflow

Use the terminal splits (`<leader>gs`, etc.) or `:terminal git ...`. Review with `git diff`, run tests, commit manually.

### AI workflow

Open `<leader>ai` (or `<leader>t`) and run any AI CLI. Keep changes incremental; review with `git diff`; run tests before committing. No API keys are stored in this config.

### Treesitter

Bundled parsers: c, lua, markdown, query, vim, vimdoc. Additional parsers may be installed manually; they are not auto-downloaded. Traditional syntax highlighting is the fallback.

### Troubleshooting

- Startup errors: `nvim --headless -u ~/.config/nvim/init.lua '+lua print("OK")' +qa`
- LSP status: `:checkhealth vim.lsp`, `:LspInfo` (if available) or `:lua =vim.lsp.get_clients()`
- Missing completion: ensure server attached and `completeopt` includes `noselect`.
- Clipboard: install `wl-clipboard` on Wayland.
- Stale parsers: see External parser cleanup.

### Rollback

```sh
rm -rf ~/.config/nvim
# restore latest backup
ls -d ~/.config/nvim.bak.* | sort | tail -1 | xargs -r -I{} cp -a {} ~/.config/nvim
```

## Known limitations

- No fuzzy finder, file tree UI beyond netrw, statusline plugin, or debugger integration.
- No automatic formatter/linter installation.
- Format-on-save off by default.
- Tree-sitter highlighting only where parsers are available.
- No AI integration inside the editor; terminal-based only.