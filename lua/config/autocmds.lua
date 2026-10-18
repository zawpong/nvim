-- Editor events. LSP wiring lives in lsp.lua; this file is not shared
-- state with it beyond the single augroup used by each module.

-- Highlight yanked text.
vim.api.nvim_create_autocmd("TextYankPost", {
  group = vim.api.nvim_create_augroup("nvim_config_autocmds", { clear = true }),
  callback = function()
    vim.highlight.on_yank({ higroup = "IncSearch", timeout = 150 })
  end,
})

-- Restore cursor position (only when Nvim remembers one).
vim.api.nvim_create_autocmd("BufReadPost", {
  group = vim.api.nvim_create_augroup("nvim_config_cursor", { clear = true }),
  callback = function(ev)
    local mark = vim.api.nvim_buf_get_mark(ev.buf, '"')
    local line_count = vim.api.nvim_buf_line_count(ev.buf)
    if mark[1] > 0 and mark[1] <= line_count then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- Filetype-specific indentation.
local indent_settings = {
  lua = { sw = 2, ts = 2, et = true },
  vim = { sw = 2, ts = 2, et = true },
  yaml = { sw = 2, ts = 2, et = true },
  json = { sw = 2, ts = 2, et = true },
  html = { sw = 2, ts = 2, et = true },
  css = { sw = 2, ts = 2, et = true },
  javascript = { sw = 2, ts = 2, et = true },
  typescript = { sw = 2, ts = 2, et = true },
  python = { sw = 4, ts = 4, et = true },
  rust = { sw = 4, ts = 4, et = true },
  c = { sw = 4, ts = 4, et = true },
  cpp = { sw = 4, ts = 4, et = true },
  go = { sw = 4, ts = 4, et = false },
  make = { sw = 8, ts = 8, et = false },
  markdown = { sw = 2, ts = 2, et = true },
}

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("nvim_config_indent", { clear = true }),
  callback = function(ev)
    local s = indent_settings[ev.match]
    if s then
      vim.bo[ev.buf].shiftwidth = s.sw
      vim.bo[ev.buf].tabstop = s.ts
      vim.bo[ev.buf].softtabstop = s.ts
      vim.bo[ev.buf].expandtab = s.et
    end
  end,
})

-- Tree-sitter highlighting with a guaranteed syntax-highlighting fallback.
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("nvim_config_treesitter", { clear = true }),
  callback = require("config.treesitter").autocmd_callback(),
})

-- Trim trailing whitespace on save, except where meaningful.
vim.api.nvim_create_autocmd("BufWritePre", {
  group = vim.api.nvim_create_augroup("nvim_config_ws", { clear = true }),
  callback = function(ev)
    local ft = vim.bo[ev.buf].filetype
    if ft == "markdown" or ft == "diff" or ft == "gitcommit" then
      return
    end
    local view = vim.fn.winsaveview()
    vim.cmd("silent! %s/\\s\\+$//e")
    vim.fn.winrestview(view)
  end,
})
