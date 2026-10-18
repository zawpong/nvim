-- Tree-sitter highlighting with native Vim syntax fallback.
--
-- Policy:
--   * Neovim ships parsers and highlight queries for only a small core set
--     (c, lua, markdown, markdown_inline, query, vim, vimdoc). Every other
--     language needs a parser AND a highlight query to be present on the
--     system; this module never downloads either at startup.
--   * Only filetypes with BOTH a usable parser and a highlight query get
--     Tree-sitter highlighting. Every other filetype keeps classic `syntax`
--     highlighting untouched (Vim syntax fallback).
--   * A missing parser/query is reported once per filetype, not on every
--     buffer.
--   * LSP semantic tokens are handled separately in lsp.lua and are enabled
--     only when the attached server supports them.
--
-- `:HighlightStatus` reports the current buffer's highlighting source.
-- `:TSStatus` reports installed versus missing parsers.

local M = {}

-- filetype -> parser (language) name. Parser name equals the language name in
-- all cases here; rows exist so the mapping stays explicit and easy to edit.
local ts_filetypes = {
  lua = "lua",
  vim = "vim",
  vimdoc = "vimdoc",
  markdown = "markdown",
  c = "c",
  query = "query",
  javascript = "javascript",
  javascriptreact = "javascript",
  typescript = "typescript",
  typescriptreact = "tsx",
  tsx = "tsx",
  json = "json",
  jsonc = "json",
  yaml = "yaml",
  yml = "yaml",
  html = "html",
  css = "css",
  scss = "css",
  python = "python",
  rust = "rust",
  go = "go",
  cpp = "cpp",
  cxx = "cpp",
  cc = "cpp",
  bash = "bash",
  sh = "bash",
  zsh = "bash",
  toml = "toml",
}

---Create a scratch buffer for parser probing.
---@return integer
local function scratch_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
  return buf
end

---True when the parser shared object for `lang` can be loaded.
---@param lang string
---@return boolean
local function parser_available(lang)
  local buf = scratch_buf()
  local ok, parser = pcall(vim.treesitter.get_parser, buf, lang)
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  return ok and parser ~= nil
end

---True when a highlight query exists for `lang`.
---@param lang string
---@return boolean
local function query_available(lang)
  local ok, query = pcall(vim.treesitter.query.get, lang, "highlights")
  return ok and query ~= nil
end

---Language name for a filetype (or the filetype itself when unmapped).
---@param filetype string
---@return string
local function language_for(filetype)
  return ts_filetypes[filetype] or filetype
end

---True when Tree-sitter highlighting can actually run for `filetype`.
---@param filetype string
---@return boolean
local function highlight_available(filetype)
  local lang = language_for(filetype)
  return parser_available(lang) and query_available(lang)
end

-- Filetypes already warned about, so we notify once, not per-buffer.
---@type table<string, boolean>
local warned = {}

---Autocmd callback for FileType.
---@return function
function M.autocmd_callback()
  return function(ev)
    local filetype = ev.match
    local lang = ts_filetypes[filetype]
    if not lang then
      return
    end
    if vim.treesitter.highlighter.active[ev.buf] then
      return
    end
    if parser_available(lang) and query_available(lang) then
      pcall(vim.treesitter.start, ev.buf, lang)
    elseif not warned[filetype] then
      warned[filetype] = true
      vim.notify(
        ("%s: no Tree-sitter parser/query; using Vim syntax highlighting.\n"
          .. "See :HighlightStatus and README (Tree-sitter parsers)."):format(filetype),
        vim.log.levels.INFO
      )
    end
  end
end

---`:TSStatus` — installed versus missing parsers.
function M.status()
  local installed = {}
  local missing = {}
  local seen = {}
  for filetype, lang in pairs(ts_filetypes) do
    if not seen[lang] then
      seen[lang] = true
      if parser_available(lang) then
        installed[#installed + 1] = lang
      else
        missing[#missing + 1] = lang
      end
    end
  end
  table.sort(installed)
  table.sort(missing)
  local lines = {
    "Tree-sitter parsers",
    "installed: " .. ( #installed > 0 and table.concat(installed, ", ") or "(none)" ),
    "missing: " .. ( #missing > 0 and table.concat(missing, ", ") or "(none)" ),
  }
  -- Also report query gaps for installed parsers.
  local no_query = {}
  for _, lang in ipairs(installed) do
    if not query_available(lang) then
      no_query[#no_query + 1] = lang
    end
  end
  table.sort(no_query)
  if #no_query > 0 then
    lines[#lines + 1] = "installed without highlight query: " .. table.concat(no_query, ", ")
  end
  vim.notify(table.concat(lines, "\n"))
end

---`:HighlightStatus` — current buffer highlighting diagnostics.
function M.highlight_status()
  local buf = vim.api.nvim_get_current_buf()
  local ft = vim.bo[buf].filetype
  local lang = language_for(ft)
  local parser_ok = parser_available(lang)
  local query_ok = query_available(lang)
  local ts_active = vim.treesitter.highlighter.active[buf] ~= nil

  local source
  if ts_active then
    source = "treesitter"
  elseif (vim.bo[buf].syntax or "") ~= "" then
    source = "vim syntax"
  else
    source = "none"
  end

  local client_names = {}
  local sem_supported = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    client_names[#client_names + 1] = client.name
    if client.server_capabilities and client.server_capabilities.semanticTokensProvider then
      sem_supported[#sem_supported + 1] = client.name
    end
  end
  table.sort(client_names)
  table.sort(sem_supported)

  local sem_enabled = false
  if #sem_supported > 0 then
    pcall(function()
      sem_enabled = vim.lsp.semantic_tokens.is_enabled({ bufnr = buf })
    end)
  end

  local lines = {
    "HighlightStatus",
    "filetype: " .. (ft ~= "" and ft or "(none)"),
    "filetype=" .. (ft ~= "" and ft or "(none)"),
    "parser: " .. lang,
    "treesitter parser available: " .. tostring(parser_ok),
    "treesitter highlight query: " .. tostring(query_ok),
    "treesitter active: " .. tostring(ts_active),
    "highlighting source: " .. source,
    "vim syntax: " .. ((vim.bo[buf].syntax or "") ~= "" and vim.bo[buf].syntax or "(none)"),
    "attached LSP clients: " .. (#client_names > 0 and table.concat(client_names, ", ") or "(none)"),
    "LSP semantic tokens supported: " .. (#sem_supported > 0 and table.concat(sem_supported, ", ") or "no"),
    "LSP semantic tokens enabled: " .. tostring(sem_enabled),
  }
  vim.notify(table.concat(lines, "\n"))
end

function M.setup()
  vim.api.nvim_create_user_command("TSStatus", M.status, { desc = "Tree-sitter parser status" })
  vim.api.nvim_create_user_command("HighlightStatus", M.highlight_status, {
    desc = "Highlighting source and parser status",
  })

  -- Start Tree-sitter for buffers already open at setup time.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local ft = vim.bo[buf].filetype
      local lang = ts_filetypes[ft]
      if lang and not vim.treesitter.highlighter.active[buf] then
        if parser_available(lang) and query_available(lang) then
          pcall(vim.treesitter.start, buf, lang)
        end
      end
    end
  end
end

-- Test hooks and public helpers.
M.ts_filetypes = ts_filetypes
M.language_for = language_for
M.parser_available = parser_available
M.query_available = query_available
M.highlight_available = highlight_available
M.has_parser = function(filetype)
  return parser_available(language_for(filetype))
end
M.has_query = function(filetype)
  return query_available(language_for(filetype))
end

return M
