-- Native Markdown presentation (zero plugins).
--
-- Refines Markdown readability using the existing palette plus Neovim's
-- built-in syntax highlighting and Tree-sitter captures. No external
-- renderer or parser is required; missing parsers fall back to :syntax.

local M = {}

local group = vim.api.nvim_create_augroup("nvim_config_markdown", { clear = true })

---Apply buffer/window-local presentation settings for a Markdown buffer.
---@param bufnr integer
function M.apply(bufnr)
  bufnr = bufnr or 0
  if bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  if vim.bo[bufnr].filetype ~= "markdown" then
    return
  end

  -- Soft wrap improves readability for prose; code blocks keep their own
  -- indentation via breakindent. `wrap` is window-local, so this is
  -- best-effort for the window opening the buffer.
  pcall(function()
    vim.wo.wrap = true
    vim.wo.linebreak = true
    vim.wo.breakindent = true
    -- Conceal redundant inline syntax (delimiters, link brackets, ...) on
    -- lines away from the cursor; the cursor line keeps delimiters visible
    -- so editing stays predictable. conceallevel 2 hides concealed text.
    vim.wo.conceallevel = 2
    vim.wo.concealcursor = ""
  end)
end

---Start Tree-sitter for Markdown when a parser is available; otherwise rely
---on classic syntax highlighting (no error).
---@param bufnr integer
local function start_treesitter(bufnr)
  if type(vim.treesitter) ~= "table" or type(vim.treesitter.start) ~= "function" then
    return
  end
  pcall(vim.treesitter.start, bufnr, "markdown")
end

function M.setup()
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "markdown",
    callback = function(ev)
      M.apply(ev.buf)
      start_treesitter(ev.buf)
    end,
  })

  -- Apply to any Markdown buffers already open at setup time.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "markdown" then
      M.apply(buf)
      start_treesitter(buf)
    end
  end

  vim.api.nvim_create_user_command("MarkdownStatus", function()
    local buf = vim.api.nvim_get_current_buf()
    local ts = false
    if vim.treesitter and vim.treesitter.highlighter and vim.treesitter.highlighter.active then
      ts = vim.treesitter.highlighter.active[buf] ~= nil
    end
    vim.notify(("markdown: filetype=%s ts=%s conceallevel=%s"):format(
      vim.bo[buf].filetype,
      tostring(ts),
      tostring(vim.wo.conceallevel)
    ))
  end, { desc = "Markdown presentation status" })
end

return M