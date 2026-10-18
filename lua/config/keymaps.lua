-- Keymaps: small, coherent, mnemonic.

local map = vim.keymap.set
local diagnostics = require("config.diagnostics")

-- Save / quit.
map("n", "<leader>w", "<cmd>w<CR>", { desc = "Save file" })
map("n", "<leader>q", "<cmd>q<CR>", { desc = "Quit window" })
map("n", "<leader>qa", "<cmd>qa<CR>", { desc = "Quit all" })

-- File exploration (native netrw).
map("n", "<leader>e", "<cmd>Lexplore<CR>", { desc = "Toggle file explorer" })

-- Buffers.
map("n", "<leader>bn", "<cmd>bnext<CR>", { desc = "Next buffer" })
map("n", "<leader>bp", "<cmd>bprevious<CR>", { desc = "Previous buffer" })

local function delete_buffer_safe()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].modified then
    vim.notify("Buffer has unsaved changes", vim.log.levels.WARN)
    return
  end
  local ok = pcall(vim.cmd, "bprevious")
  if not ok or vim.api.nvim_get_current_buf() == buf then
    vim.cmd("enew")
  end
  pcall(vim.cmd, "bdelete " .. buf)
end
map("n", "<leader>bd", delete_buffer_safe, { desc = "Delete buffer (safe)" })

-- Windows / splits.
map("n", "<leader>sv", "<cmd>vsplit<CR>", { desc = "Vertical split" })
map("n", "<leader>sh", "<cmd>split<CR>", { desc = "Horizontal split" })
map("n", "<leader>sc", "<cmd>close<CR>", { desc = "Close window" })
map("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Move to lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Move to upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })

-- Terminal.
map("n", "<leader>t", "<cmd>terminal<CR>", { desc = "Open terminal" })
map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Terminal to normal mode" })

-- Diagnostics.
map("n", "[d", function() vim.diagnostic.goto_prev() end, { desc = "Previous diagnostic" })
map("n", "]d", function() vim.diagnostic.goto_next() end, { desc = "Next diagnostic" })
map("n", "<leader>d", function() vim.diagnostic.open_float() end, { desc = "Diagnostic details" })
map("n", "<leader>dl", function() vim.diagnostic.setloclist() end, { desc = "Diagnostics to location list" })
map("n", "<leader>dv", diagnostics.toggle_virtual_text, { desc = "Toggle diagnostic virtual text" })

-- Quickfix / location list.
map("n", "[q", "<cmd>silent! cprev<CR>", { desc = "Previous quickfix" })
map("n", "]q", "<cmd>silent! cnext<CR>", { desc = "Next quickfix" })
map("n", "[l", "<cmd>silent! lprev<CR>", { desc = "Previous location" })
map("n", "]l", "<cmd>silent! lnext<CR>", { desc = "Next location" })
map("n", "<leader>co", "<cmd>copen<CR>", { desc = "Open quickfix" })
map("n", "<leader>cc", "<cmd>cclose<CR>", { desc = "Close quickfix" })
map("n", "<leader>lo", "<cmd>lopen<CR>", { desc = "Open location list" })
map("n", "<leader>lc", "<cmd>lclose<CR>", { desc = "Close location list" })

-- Search highlight.
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- Formatting (LSP).
map("n", "<leader>f", function()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if #clients == 0 then
    vim.notify("No LSP client attached", vim.log.levels.INFO)
    return
  end
  vim.lsp.buf.format({ async = true })
end, { desc = "Format buffer (LSP)" })

-- Git helpers (external commands in terminal split).
local function git_term(cmd)
  vim.cmd("split | terminal " .. cmd)
end
map("n", "<leader>gs", function() git_term("git status") end, { desc = "Git status" })
map("n", "<leader>gd", function() git_term("git diff") end, { desc = "Git diff" })
map("n", "<leader>gD", function() git_term("git diff --check") end, { desc = "Git diff --check" })
map("n", "<leader>gl", function() git_term("git log --oneline --decorate -20") end, { desc = "Git log" })

-- AI assistant terminal (provider-agnostic).
map("n", "<leader>ai", function()
  local candidates = { "claude", "codex", "gemini", "opencode" }
  local chosen
  for _, name in ipairs(candidates) do
    if vim.fn.executable(name) == 1 then
      chosen = name
      break
    end
  end
  if chosen then
    vim.cmd("split | terminal " .. chosen)
  else
    vim.notify("No AI CLI found; open terminal and run your tool", vim.log.levels.INFO)
    vim.cmd("split | terminal")
  end
end, { desc = "AI assistant terminal" })