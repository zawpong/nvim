-- Neovim native, zero-plugin configuration.
-- Modules are loaded in deterministic order; each owns one responsibility.
-- utils.lua has no setup and is required implicitly by the other modules.

require("config.options")
require("config.highlights").setup()
require("config.statusline")
require("config.git_context").setup()
require("config.diagnostics")
require("config.treesitter").setup()
require("config.search").setup()
require("config.multicursor").setup()
require("config.images").setup()
require("config.keymaps")
require("config.autocmds")
require("config.lsp").setup()
