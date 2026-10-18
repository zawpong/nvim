-- Native LSP configuration (vim.lsp.config / vim.lsp.enable; 0.11+ API).
--
-- Policy:
--   * Server executables are detected BEFORE enabling; nothing is downloaded
--     at startup, and missing servers are simply not enabled.
--   * Format-on-save stays OFF by default (vim.g.format_on_save = false in
--     options.lua); buffer formatting is available via <leader>=.
--   * All LSP-side autocmd registration happens here, exactly once.
--
-- Server installation is documented in README.md (separate from editor
-- installation).

local u = require("config.utils")

local M = {}

---Server definitions: { config = {...}, cmd_names = {exe, ...} }.
---Enable when every cmd_names entry is an executable.
local servers = {
  lua_ls = {
    cmd_names = { "lua-language-server" },
    config = {
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
    },
  },
  gopls = {
    cmd_names = { "gopls" },
    config = {
      cmd = { "gopls" },
      filetypes = { "go", "gomod", "gowork", "gotmpl" },
      root_markers = { "go.mod", "go.work", ".git" },
    },
  },
  basedpyright = {
    cmd_names = { "basedpyright-langserver" },
    config = {
      cmd = { "basedpyright-langserver", "--stdio" },
      filetypes = { "python" },
      root_markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" },
      settings = {
        basedpyright = {
          analysis = { autoSearchPaths = true, useLibraryCodeForTypes = true },
        },
      },
    },
  },
  ruff = {
    -- Fallback python server when basedpyright is absent (fast, common).
    cmd_names = { "ruff" },
    config = {
      cmd = { "ruff", "server" },
      filetypes = { "python" },
      root_markers = { "pyproject.toml", ".git" },
    },
  },
  rust_analyzer = {
    cmd_names = { "rust-analyzer" },
    config = {
      cmd = { "rust-analyzer" },
      filetypes = { "rust" },
      root_markers = { "Cargo.toml", ".git" },
    },
  },
  clangd = {
    cmd_names = { "clangd" },
    config = {
      cmd = { "clangd", "--background-index" },
      filetypes = { "c", "cpp", "objc", "objcpp" },
      root_markers = { "compile_commands.json", ".git" },
    },
  },
}

---Enabled names in deterministic order (for :LspStatus).
local enabled = {}

-- Track which buffers/clients have completion enabled, for safe teardown.
M._completion_enabled = {}
M._inline_enabled = {}

---Enable native LSP completion for a client/buffer (guarded).
---@param client_id integer
---@param bufnr integer
---@return boolean
function M.enable_completion(client_id, bufnr)
  bufnr = bufnr or 0
  if bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  local client = vim.lsp.get_client_by_id(client_id)
  if not client or not client:supports_method("textDocument/completion") then
    return false
  end
  if type(vim.lsp.completion) ~= "table" or type(vim.lsp.completion.enable) ~= "function" then
    return false
  end
  local ok = pcall(vim.lsp.completion.enable, true, client_id, bufnr, {
    autotrigger = true,
    commit_characters = true,
  })
  if ok then
    M._completion_enabled[bufnr] = M._completion_enabled[bufnr] or {}
    M._completion_enabled[bufnr][client_id] = true
  end
  return ok
end

---Disable native LSP completion for a client/buffer (guarded).
---@param client_id integer
---@param bufnr integer
---@return boolean
function M.disable_completion(client_id, bufnr)
  bufnr = bufnr or 0
  if bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  if type(vim.lsp.completion) ~= "table" or type(vim.lsp.completion.enable) ~= "function" then
    return false
  end
  local ok = pcall(vim.lsp.completion.enable, false, client_id, bufnr)
  if M._completion_enabled[bufnr] then
    M._completion_enabled[bufnr][client_id] = nil
  end
  return ok
end

---Enable inline completion for a client/buffer when supported (guarded).
---@param client_id integer
---@param bufnr integer
---@return boolean
function M.enable_inline_completion(client_id, bufnr)
  bufnr = bufnr or 0
  if bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  local client = vim.lsp.get_client_by_id(client_id)
  if not client or not client:supports_method("textDocument/inlineCompletion") then
    return false
  end
  if not (vim.lsp.inline_completion and type(vim.lsp.inline_completion.enable) == "function") then
    return false
  end
  local ok = pcall(vim.lsp.inline_completion.enable, true, {
    bufnr = bufnr,
    client_id = client_id,
  })
  if ok then
    M._inline_enabled[bufnr] = M._inline_enabled[bufnr] or {}
    M._inline_enabled[bufnr][client_id] = true
  end
  return ok
end

---Disable inline completion for a client/buffer (guarded).
---@param client_id integer
---@param bufnr integer
---@return boolean
function M.disable_inline_completion(client_id, bufnr)
  bufnr = bufnr or 0
  if bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  if not (vim.lsp.inline_completion and type(vim.lsp.inline_completion.enable) == "function") then
    return false
  end
  local ok = pcall(vim.lsp.inline_completion.enable, false, {
    bufnr = bufnr,
    client_id = client_id,
  })
  if M._inline_enabled[bufnr] then
    M._inline_enabled[bufnr][client_id] = nil
  end
  return ok
end

function M.attached_clients(bufnr)
  return vim.lsp.get_clients({ bufnr = bufnr or 0 })
end

---`:LspStatus` — which servers are enabled for this session, and which are
---attached to the current buffer; lists enabled-but-not-current servers to
---help debug why a server did not attach.
function M.status()
  local lines = {}
  if #enabled == 0 then
    lines[#lines + 1] = "no LSP servers enabled (executables not on PATH)"
  end
  for _, name in ipairs(enabled) do
    local attached = {}
    for _, c in ipairs(vim.lsp.get_clients({ bufnr = 0, name = name })) do
      attached[#attached + 1] = tostring(c.id)
    end
    lines[#lines + 1] = ("%s: enabled%s"):format(
      name,
      #attached > 0 and (" (attached: id %s)"):format(table.concat(attached, ", ")) or ""
    )
  end
  local cur = vim.lsp.get_clients({ bufnr = 0 })
  if #cur > 0 then
    lines[#lines + 1] = ("current buffer: %d client(s)"):format(#cur)
  end
  vim.notify(table.concat(lines, "\n"))
end

---Per-buffer LSP behavior, registered exactly once per attach.
function M.setup()
  for name, def in pairs(servers) do
    local ok = true
    for _, exe in ipairs(def.cmd_names) do
      if not u.has(exe) then
        ok = false
        break
      end
    end
    if ok then
      vim.lsp.config(name, def.config)
      vim.lsp.enable(name)
      enabled[#enabled + 1] = name
    end
  end

  vim.api.nvim_create_user_command("LspStatus", M.status, { desc = "LSP client status" })
  vim.api.nvim_create_user_command("LspCompletionStatus", function()
    local lines = {}
    for buf, clients in pairs(M._completion_enabled) do
      for cid, v in pairs(clients) do
        if v then lines[#lines + 1] = ("buf %d client %d: completion enabled"):format(buf, cid) end
      end
    end
    if #lines == 0 then lines[#lines + 1] = "no LSP completion enabled" end
    vim.notify(table.concat(lines, "\\n"))
  end, { desc = "LSP completion status" })

  -- Manual trigger for native LSP completion (Ctrl-Space). Non-conflicting
  -- with Tab/Enter/Ctrl-Y and snippet expansion.
  vim.keymap.set("i", "<C-Space>", function()
    if type(vim.lsp.completion) == "table" and type(vim.lsp.completion.get) == "function" then
      vim.lsp.completion.get()
    end
  end, { desc = "Trigger LSP completion" })

  local format_group = vim.api.nvim_create_augroup("nvim_config_lsp_format", { clear = true })

  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("nvim_config_lsp_attach", { clear = true }),
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

      -- Native LSP completion (trigger characters, not every keystroke).
      -- Guarded so a missing API or unsupported client degrades gracefully.
      if client:supports_method("textDocument/completion") then
        pcall(vim.lsp.completion.enable, true, client.id, buf, {
          autotrigger = true,
          commit_characters = true,
        })
        M._completion_enabled[buf] = M._completion_enabled[buf] or {}
        M._completion_enabled[buf][client.id] = true
      end

      -- Optional inline completion: only when both Nvim and the server
      -- support it. Kept independent of the regular completion menu.
      if vim.lsp.inline_completion
        and type(vim.lsp.inline_completion.enable) == "function"
        and client:supports_method("textDocument/inlineCompletion") then
        pcall(vim.lsp.inline_completion.enable, true, {
          bufnr = buf,
          client_id = client.id,
        })
        M._inline_enabled[buf] = M._inline_enabled[buf] or {}
        M._inline_enabled[buf][client.id] = true
      end

      -- Format-on-save stays opt-in (vim.g.format_on_save in options.lua).
      -- One autocmd per buffer, scoped to the triggering client.
      if vim.g.format_on_save and client:supports_method("textDocument/formatting") then
        vim.api.nvim_create_autocmd("BufWritePre", {
          group = format_group,
          buffer = buf,
          callback = function()
            vim.lsp.buf.format({ bufnr = buf, id = client.id, timeout_ms = 1000 })
          end,
        })
      end
    end,
  })

  -- Safe teardown when a client detaches.
  vim.api.nvim_create_autocmd("LspDetach", {
    group = vim.api.nvim_create_augroup("nvim_config_lsp_detach", { clear = true }),
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      if not client then
        return
      end
      local buf = ev.buf
      M.disable_completion(client.id, buf)
      M.disable_inline_completion(client.id, buf)
    end,
  })
end

return M
