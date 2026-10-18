-- Native LSP configuration (Neovim 0.11+ API).

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