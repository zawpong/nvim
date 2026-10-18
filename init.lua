-- Neovim native, zero-plugin configuration.
-- Modules are loaded in deterministic order; each owns one responsibility.

require("config.options")
require("config.statusline")
require("config.diagnostics")
require("config.keymaps")
require("config.autocmds")
require("config.lsp")