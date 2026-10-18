-- Neovim native, zero-plugin configuration.
-- Single self-contained file. No third-party plugins, no network at startup.

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------
local opt = vim.opt

vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.g.format_on_save = false

opt.number = true
opt.relativenumber = true
opt.cursorline = true
opt.signcolumn = "yes"
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.wrap = false
opt.linebreak = true

opt.expandtab = true
opt.shiftwidth = 4
opt.tabstop = 4
opt.softtabstop = 4
opt.smartindent = true
opt.autoindent = true

opt.ignorecase = true
opt.smartcase = true
opt.incsearch = true
opt.hlsearch = true

opt.splitbelow = true
opt.splitright = true

opt.mouse = "a"

opt.completeopt = "menu,menuone,noselect,popup"
opt.pumheight = 12

opt.wildmenu = true
opt.wildmode = "longest:full,full"

opt.updatetime = 300
opt.timeoutlen = 400

local state = vim.fn.stdpath("state")
local backup_dir = state .. "/backup"
local swap_dir = state .. "/swap"
local undo_dir = state .. "/undo"
for _, dir in ipairs({ backup_dir, swap_dir, undo_dir }) do
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
end
opt.backup = false
opt.writebackup = true
opt.swapfile = true
opt.undofile = true
opt.backupdir = backup_dir .. "//"
opt.directory = swap_dir .. "//"
opt.undodir = undo_dir .. "//"

opt.termguicolors = true
opt.laststatus = 2
opt.showmode = false
opt.cmdheight = 1

opt.clipboard = "unnamedplus"

vim.g.netrw_banner = 0
vim.g.netrw_liststyle = 3
vim.g.netrw_winsize = 25
vim.g.netrw_keepdir = 1

function _G.nvim_statusline()
  local counts = vim.diagnostic.count(0)
  local parts = {}
  local e = counts[vim.diagnostic.severity.ERROR] or 0
  local w = counts[vim.diagnostic.severity.WARN] or 0
  if e > 0 then table.insert(parts, "E:" .. e) end
  if w > 0 then table.insert(parts, "W:" .. w) end
  local diag = table.concat(parts, " ")
  local line = "%<%f %h%m%r"
  if diag ~= "" then
    line = line .. " [" .. diag .. "]"
  end
  line = line .. "%=%y  %-14.(%l,%c%V%)  %P"
  return line
end
opt.statusline = "%!v:lua.nvim_statusline()"

vim.cmd.colorscheme("habamax")

-- ---------------------------------------------------------------------------
-- Diagnostics
-- ---------------------------------------------------------------------------
vim.diagnostic.config({
  severity_sort = true,
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "E",
      [vim.diagnostic.severity.WARN] = "W",
      [vim.diagnostic.severity.INFO] = "I",
      [vim.diagnostic.severity.HINT] = "H",
    },
  },
  underline = true,
  virtual_text = { spacing = 2, prefix = "●" },
  float = { border = "rounded", source = "if_many" },
  update_in_insert = false,
})

local virtual_text_enabled = true
local function toggle_virtual_text()
  virtual_text_enabled = not virtual_text_enabled
  vim.diagnostic.config({ virtual_text = virtual_text_enabled and { spacing = 2, prefix = "●" } or false })
  vim.notify("Diagnostic virtual text: " .. (virtual_text_enabled and "on" or "off"))
end

-- ---------------------------------------------------------------------------
-- Keymaps
-- ---------------------------------------------------------------------------
local map = vim.keymap.set

map("n", "<leader>w", "<cmd>w<CR>", { desc = "Save file" })
map("n", "<leader>q", "<cmd>q<CR>", { desc = "Quit window" })
map("n", "<leader>qa", "<cmd>qa<CR>", { desc = "Quit all" })

map("n", "<leader>e", "<cmd>Lexplore<CR>", { desc = "Toggle file explorer" })

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

map("n", "<leader>sv", "<cmd>vsplit<CR>", { desc = "Vertical split" })
map("n", "<leader>sh", "<cmd>split<CR>", { desc = "Horizontal split" })
map("n", "<leader>sc", "<cmd>close<CR>", { desc = "Close window" })
map("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Move to lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Move to upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })

map("n", "<leader>t", "<cmd>terminal<CR>", { desc = "Open terminal" })
map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Terminal to normal mode" })

map("n", "[d", function() vim.diagnostic.goto_prev() end, { desc = "Previous diagnostic" })
map("n", "]d", function() vim.diagnostic.goto_next() end, { desc = "Next diagnostic" })
map("n", "<leader>d", function() vim.diagnostic.open_float() end, { desc = "Diagnostic details" })
map("n", "<leader>dl", function() vim.diagnostic.setloclist() end, { desc = "Diagnostics to location list" })
map("n", "<leader>dv", toggle_virtual_text, { desc = "Toggle diagnostic virtual text" })

map("n", "[q", "<cmd>silent! cprev<CR>", { desc = "Previous quickfix" })
map("n", "]q", "<cmd>silent! cnext<CR>", { desc = "Next quickfix" })
map("n", "[l", "<cmd>silent! lprev<CR>", { desc = "Previous location" })
map("n", "]l", "<cmd>silent! lnext<CR>", { desc = "Next location" })
map("n", "<leader>co", "<cmd>copen<CR>", { desc = "Open quickfix" })
map("n", "<leader>cc", "<cmd>cclose<CR>", { desc = "Close quickfix" })
map("n", "<leader>lo", "<cmd>lopen<CR>", { desc = "Open location list" })
map("n", "<leader>lc", "<cmd>lclose<CR>", { desc = "Close location list" })

map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

map("n", "<leader>f", function()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if #clients == 0 then
    vim.notify("No LSP client attached", vim.log.levels.INFO)
    return
  end
  vim.lsp.buf.format({ async = true })
end, { desc = "Format buffer (LSP)" })

local function git_term(cmd)
  vim.cmd("split | terminal " .. cmd)
end
map("n", "<leader>gs", function() git_term("git status") end, { desc = "Git status" })
map("n", "<leader>gd", function() git_term("git diff") end, { desc = "Git diff" })
map("n", "<leader>gD", function() git_term("git diff --check") end, { desc = "Git diff --check" })
map("n", "<leader>gl", function() git_term("git log --oneline --decorate -20") end, { desc = "Git log" })

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

-- ---------------------------------------------------------------------------
-- Autocmds
-- ---------------------------------------------------------------------------
local group = vim.api.nvim_create_augroup("nvim_config", { clear = true })

vim.api.nvim_create_autocmd("TextYankPost", {
  group = group,
  callback = function()
    vim.highlight.on_yank({ higroup = "IncSearch", timeout = 150 })
  end,
})

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

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  callback = function(ev)
    pcall(vim.treesitter.start, ev.buf)
  end,
})

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

-- ---------------------------------------------------------------------------
-- LSP
-- ---------------------------------------------------------------------------
local function has(cmd)
  return vim.fn.executable(cmd) == 1
end

vim.lsp.config("lua_ls", {
  cmd = { "lua-language-server" },
  filetypes = { "lua" },
  root_markers = { { ".luarc.json", ".luarc.jsonc" }, ".git" },
  settings = {
    Lua = {
      runtime = { version = "LuaJIT" },
      diagnostics = { globals = { "vim" } },
      workspace = { checkThirdParty = false },
      telemetry = { enable = false },
    },
  },
})
if has("lua-language-server") then vim.lsp.enable("lua_ls") end

vim.lsp.config("gopls", {
  cmd = { "gopls" },
  filetypes = { "go", "gomod", "gowork", "gotmpl" },
  root_markers = { "go.mod", "go.work", ".git" },
})
if has("gopls") then vim.lsp.enable("gopls") end

vim.lsp.config("basedpyright", {
  cmd = { "basedpyright-langserver", "--stdio" },
  filetypes = { "python" },
  root_markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" },
  settings = {
    basedpyright = {
      analysis = { autoSearchPaths = true, useLibraryCodeForTypes = true },
    },
  },
})
if has("basedpyright-langserver") then vim.lsp.enable("basedpyright") end

vim.lsp.config("rust_analyzer", {
  cmd = { "rust-analyzer" },
  filetypes = { "rust" },
  root_markers = { "Cargo.toml", ".git" },
})
if has("rust-analyzer") then vim.lsp.enable("rust_analyzer") end

vim.lsp.config("clangd", {
  cmd = { "clangd", "--background-index" },
  filetypes = { "c", "cpp", "objc", "objcpp" },
  root_markers = { "compile_commands.json", ".git" },
})
if has("clangd") then vim.lsp.enable("clangd") end