-- Native, zero-plugin auto-pairing for insert mode.
--
-- Maps the opening/closing characters themselves; no Tab/Enter/Ctrl-Y are
-- touched, so LSP completion, snippets and the existing picker keep working.

local M = {}

M.enabled = true

local pair_map = {
  ["("] = ")",
  ["["] = "]",
  ["{"] = "}",
  ['"'] = '"',
  ["'"] = "'",
  ["`"] = "`",
}

-- Reverse lookup: closing -> opening.
local open_for = {}
for open, close in pairs(pair_map) do
  open_for[close] = open
end

local function termcodes(s)
  return vim.api.nvim_replace_termcodes(s, true, true, true)
end

local function prev_char()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] -- 0-based
  if col == 0 then
    return ""
  end
  return line:sub(col, col)
end

local function next_char()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] -- 0-based; char after cursor
  if col >= #line then
    return ""
  end
  return line:sub(col + 1, col + 1)
end

local function allow_pair(open)
  if not M.enabled then
    return false
  end
  -- Never interfere while the completion menu is open.
  if vim.fn.pumvisible() == 1 then
    return false
  end
  -- Brackets always pair.
  if open == "(" or open == "[" or open == "{" then
    return true
  end
  -- Quotes/backticks: avoid pairing in word contexts or when escaped.
  local p = prev_char()
  if p == "\\" then
    return false
  end
  if p:match("[%w_]") then
    return false
  end
  local n = next_char()
  if n:match("[%w_]") then
    return false
  end
  return true
end

---Handle an opening (or quote) keystroke. Returns text to insert (expr).
---@param char string
---@return string
function M.handle_open(char)
  if char == "`" then
    -- Avoid pairing inside a run of backticks (triple backticks, code
    -- fences) and let a literal backtick through.
    if prev_char() == "`" then
      return "`"
    end
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    if col >= 2 and line:sub(col - 1, col) == "``" then
      return "`"
    end
    if not allow_pair("`") then
      return "`"
    end
    if next_char() == "`" then
      return termcodes("<Right>")
    end
    return "`" .. "`" .. termcodes("<Left>")
  end

  local close = pair_map[char]
  if not close or not allow_pair(char) then
    return char
  end
  -- Insert the pair and leave the cursor between them.
  return char .. close .. termcodes("<Left>")
end

---Handle a closing keystroke: skip over an existing auto-inserted close.
---@param char string
---@return string
function M.handle_close(char)
  if not M.enabled or vim.fn.pumvisible() == 1 then
    return char
  end
  if prev_char() == "\\" then
    return char
  end
  if next_char() == char then
    return termcodes("<Right>")
  end
  return char
end

---Handle Backspace: remove both chars of an empty auto-inserted pair.
---@return string
function M.handle_backspace()
  if not M.enabled or vim.fn.pumvisible() == 1 then
    return termcodes("<BS>")
  end
  local p = prev_char()
  local n = next_char()
  if p ~= "" and pair_map[p] == n then
    return termcodes("<BS><Del>")
  end
  return termcodes("<BS>")
end

function M.setup()
  -- Opening pairs (and quotes/backticks, which are their own open+close).
  for open, _ in pairs(pair_map) do
    vim.keymap.set("i", open, function()
      return M.handle_open(open)
    end, { expr = true, desc = "Auto-pair " .. open })
  end

  -- Closing pairs: skip when the next char is the same closing delimiter.
  for _, close in pairs(pair_map) do
    -- Avoid duplicate mappings for chars already mapped as openers.
    if pair_map[close] == nil then
      vim.keymap.set("i", close, function()
        return M.handle_close(close)
      end, { expr = true, desc = "Auto-pair skip " .. close })
    end
  end

  -- For chars that are both opener and closer (quotes/backticks), the opener
  -- mapping above already handles typing them; add skip behavior by making
  -- their handler context-aware: if the next char is the same, skip instead.
  -- Re-map those specific chars with a combined handler.
  for _, q in ipairs({ '"', "'", "`" }) do
    vim.keymap.set("i", q, function()
      if M.enabled and vim.fn.pumvisible() ~= 1 and next_char() == q and prev_char() ~= "\\" then
        return termcodes("<Right>")
      end
      return M.handle_open(q)
    end, { expr = true, desc = "Auto-pair quote " .. q })
  end

  -- Backspace handling for empty pairs.
  vim.keymap.set("i", "<BS>", function()
    return M.handle_backspace()
  end, { expr = true, desc = "Auto-pair backspace" })

  vim.api.nvim_create_user_command("AutoPairsToggle", function()
    M.enabled = not M.enabled
    vim.notify("Auto-pairs: " .. (M.enabled and "on" or "off"))
  end, { desc = "Toggle auto-pairs" })
end

return M