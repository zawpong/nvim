-- Autocommands.

local group = vim.api.nvim_create_augroup("nvim_config", { clear = true })

-- Highlight yanked text.
vim.api.nvim_create_autocmd("TextYankPost", {
  group = group,
  callback = function()
    vim.highlight.on_yank({ higroup = "IncSearch", timeout = 150 })
  end,
})

-- Restore cursor position.
vim.api.nvim_create_autocmd("BufReadPost", {
  group = group,
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
  group = group,
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

-- Tree-sitter highlighting with graceful fallback to traditional syntax.
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  callback = function(ev)
    pcall(vim.treesitter.start, ev.buf)
  end,
})

-- Trim trailing whitespace on save, except where meaningful.
vim.api.nvim_create_autocmd("BufWritePre", {
  group = group,
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

-- LSP attach: keymaps, completion, optional format-on-save.
vim.api.nvim_create_autocmd("LspAttach", {
  group = group,
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if not client then
      return
    end
    local buf = ev.buf

    local function bmap(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc, silent = true })
    end

    bmap("n", "gd", vim.lsp.buf.definition, "Go to definition")
    bmap("n", "gD", vim.lsp.buf.declaration, "Go to declaration")
    bmap("n", "gr", vim.lsp.buf.references, "References")
    bmap("n", "gi", vim.lsp.buf.implementation, "Implementation")
    bmap("n", "gt", vim.lsp.buf.type_definition, "Type definition")
    bmap("n", "K", vim.lsp.buf.hover, "Hover documentation")
    bmap("n", "<leader>rn", vim.lsp.buf.rename, "Rename symbol")
    bmap("n", "<leader>ca", vim.lsp.buf.code_action, "Code action")
    bmap("n", "<leader>ds", vim.lsp.buf.document_symbol, "Document symbols")
    bmap("n", "<leader>ws", vim.lsp.buf.workspace_symbol, "Workspace symbols")

    if client:supports_method("textDocument/completion") then
      vim.lsp.completion.enable(true, client.id, buf, { autotrigger = true })
    end

    if vim.g.format_on_save and client:supports_method("textDocument/formatting") then
      vim.api.nvim_create_autocmd("BufWritePre", {
        group = group,
        buffer = buf,
        callback = function()
          vim.lsp.buf.format({ bufnr = buf, id = client.id, timeout_ms = 1000 })
        end,
      })
    end
  end,
})