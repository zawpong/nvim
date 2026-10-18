-- Tree-sitter highlighting using bundled parsers only.
--
-- Policy:
--   * Neovim bundles parsers for a core set of languages (c, lua, vim,
--     vimdoc, markdown, query, …); we never download parsers at startup and
--     never install third-party grammar tooling.
--   * Only languages with BOTH a bundled/installed parser AND filetype
--     support get treesitter highlighting; every other filetype keeps its
--     classic `syntax` highlighting untouched.
--   * A missing parser is reported once per filetype, not on every open.
--
-- `:TSStatus` shows the parsers available and which filetypes use treesitter.

local u = require("config.utils")

local M = {}

-- filetype -> parser name (parser name equals the filetype in all cases here;
-- rows exist so the mapping stays explicit and easy to edit).
local ts_filetypes = {
  lua = "lua",
  vim = "vim",
  vimdoc = "vimdoc",
  markdown = "markdown",
  c = "c",
  query = "query",
  javascript = "javascript",
  typescript = "typescript",
  tsx = "tsx",
  json = "json",
  yaml = "yaml",
  html = "html",
  css = "css",
  python = "python",
  rust = "rust",
  go = "go",
  cpp = "cpp",
  bash = "bash",
  checkhealth = "vimdoc",
}

---@param filetype string
---@return boolean
local function has_parser(filetype)
  return pcall(vim.treesitter.language.add, ts_filetypes[filetype] or filetype)
end

-- Filetypes already warned about, so we notify once, not per-buffer.
---@type table<string, boolean>
local warned = {}

---@return function autocmd callback for FileType
function M.autocmd_callback()
  return function(ev)
    local filetype = ev.match
    if not ts_filetypes[filetype] then
      return
    end
    if has_parser(filetype) then
      pcall(vim.treesitter.start, ev.buf)
    elseif not warned[filetype] then
      warned[filetype] = true
      vim.notify(
        ([[%s: no tree-sitter parser; using classic syntax highlighting.
Install one with `:TSInstall %s` if the nvim-treesitter runtime is available.]]):format(
          filetype,
          ts_filetypes[filetype]
        ),
        vim.log.levels.INFO
      )
    end
  end
end

---`:TSStatus` — report which treesitter parsers are actually usable.
function M.status()
  local installed = {}
  for filetype, parser in pairs(ts_filetypes) do
    if has_parser(filetype) then
      installed[#installed + 1] = parser
    end
  end
  table.sort(installed)
  vim.notify(
    ("treesitter parsers available: %s\nall other filetypes fall back to :syntax"):format(
      table.concat(installed, ", ")
    )
  )
end

function M.setup()
  vim.api.nvim_create_user_command("TSStatus", M.status, { desc = "Tree-sitter parser status" })
end

-- Keep module-level test hooks tidy.
M.has_parser = has_parser

return M
