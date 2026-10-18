#!/usr/bin/env bash
set -euo pipefail
CONFIG="${1:-$HOME/.config/nvim/init.lua}"
nvim --headless -u "$CONFIG" '+lua assert(true)' +qa
echo "headless startup: OK"

nvim --headless -u "$CONFIG" '+lua for _,m in ipairs({"config.options","config.statusline","config.diagnostics","config.keymaps","config.autocmds","config.lsp"}) do require(m) end; print("modules: OK")' +qa
echo "module load: OK"

for f in /tmp/opencode/nvimtest/test.lua; do
  [ -f "$f" ] || continue
  nvim --headless -u "$CONFIG" "$f" '+lua vim.wait(1500)' '+lua assert(#vim.lsp.get_clients({bufnr=0}) >= 1, "no LSP client")' +qa
  echo "LSP attach ($f): OK"
done