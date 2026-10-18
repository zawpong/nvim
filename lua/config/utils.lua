-- Shared helpers. Only add here what is genuinely used by more than one module.

local M = {}

---True when `cmd` is an executable on PATH.
---@param cmd string
---@return boolean
function M.has(cmd)
  return vim.fn.executable(cmd) == 1
end

---True when the running Nvim supports the multicursor features new in 0.13.
---Probed at runtime rather than assumed, because 0.13 was nightly-only at the
---time this config was written; behavior is guarded, never fabricated.
---@return boolean
function M.has_native_multicursor()
  if M._has_native_multicursor == nil then
    local ok = vim.fn.has("nvim-0.13") == 1
    if not ok then
      -- 0.13 nightlies expose the runtime module even early in the cycle.
      ok = pcall(require, "vim._core.mcursor")
    end
    M._has_native_multicursor = ok
  end
  return M._has_native_multicursor
end

---Project root for the current buffer: first marker found upward; Git .git/
---falls back to the buffer's directory when outside a repository.
---@param bufnr integer
---@return string
function M.project_root(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr or 0)
  local dir = (name ~= "" and vim.fs.dirname(name) or vim.uv.cwd()) or vim.uv.cwd()
  local markers = { ".git", "go.mod", "Cargo.toml", "pyproject.toml", "Makefile" }
  local found = vim.fs.find(markers, {
    upward = true,
    stop = vim.uv.os_homedir(),
    path = dir,
    limit = 1,
  })[1]
  if found then
    return vim.fs.dirname(found)
  end
  return dir
end

---Shell-quoted list suited for `fzf`-style external tools.
---We avoid string-built shell commands; this exists only for the few
---integrations where a quoted list is genuinely needed.
---@param items string[]
---@return string
function M.shellescape_list(items)
  local parts = {}
  for _, i in ipairs(items) do
    parts[#parts + 1] = vim.fn.shellescape(i)
  end
  return table.concat(parts, " ")
end

return M
