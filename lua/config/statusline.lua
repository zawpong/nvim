-- Compact statusline with a clear information hierarchy.
--
-- The string is built per window from cheap, already-available data only
-- (buffer name, modified/read-only state, diagnostic counts). No shell/Git/
-- subprocess calls and no per-keystroke work beyond normal redraws.

local opt = vim.opt

local mode_names = {
  n = "NORMAL",
  i = "INSERT",
  v = "VISUAL",
  V = "V-LINE",
  ["\22"] = "V-BLOCK",
  c = "COMMAND",
  t = "TERMINAL",
  R = "REPLACE",
  Rv = "V-REPLACE",
  s = "SELECT",
  S = "S-LINE",
  ["\19"] = "S-BLOCK",
}

local mode_groups = {
  n = "StatusLineModeNormal",
  i = "StatusLineModeInsert",
  ic = "StatusLineModeInsert",
  ix = "StatusLineModeInsert",
  v = "StatusLineModeVisual",
  V = "StatusLineModeVisual",
  ["\22"] = "StatusLineModeVisual",
  s = "StatusLineModeVisual",
  S = "StatusLineModeVisual",
  ["\19"] = "StatusLineModeVisual",
  c = "StatusLineModeCommand",
  t = "StatusLineModeTerminal",
  R = "StatusLineModeReplace",
  Rv = "StatusLineModeReplace",
}

local function mode_group(mode)
  if mode_groups[mode] then
    return mode_groups[mode]
  end
  if mode:sub(1, 1) == "i" then
    return "StatusLineModeInsert"
  end
  if mode:sub(1, 1) == "v" or mode:sub(1, 1) == "V" or mode:sub(1, 1) == "s" then
    return "StatusLineModeVisual"
  end
  if mode:sub(1, 1) == "R" then
    return "StatusLineModeReplace"
  end
  if mode:sub(1, 1) == "c" then
    return "StatusLineModeCommand"
  end
  if mode:sub(1, 1) == "t" then
    return "StatusLineModeTerminal"
  end
  return "StatusLineMode"
end

local function is_active(win)
  if type(win) ~= "number" or not vim.api.nvim_win_is_valid(win) then
    return true
  end
  return win == vim.api.nvim_get_current_win()
end

function _G.nvim_statusline()
  local win = vim.g.statusline_winid
  if type(win) ~= "number" or not vim.api.nvim_win_is_valid(win) then
    win = vim.api.nvim_get_current_win()
  end
  local active = is_active(win)
  local buf = vim.api.nvim_win_get_buf(win)

  local mode_hl = active and mode_group(vim.fn.mode()) or "StatusLineNC"
  local file_hl = active and "StatusLineFile" or "StatusLineNC"
  local info_hl = active and "StatusLineInfo" or "StatusLineNC"

  local parts = {}

  -- Mode indicator only; color is mode-specific.
  if active then
    local mode = mode_names[vim.fn.mode()] or vim.fn.mode()
    parts[#parts + 1] = "%#" .. mode_hl .. "# " .. mode .. " "
  end

  -- Filename and modified/read-only state.
  parts[#parts + 1] = "%#" .. file_hl .. "# %<%f %m%r"

  -- Repository context (cached; never runs Git on redraw).
  local git_segment = require("config.git_context").line(buf, active)
  if git_segment ~= "" then
    parts[#parts + 1] = "  " .. git_segment
  end

  -- Diagnostics when nonzero.
  local counts = vim.diagnostic.count(buf)
  local e = counts[vim.diagnostic.severity.ERROR] or 0
  local w = counts[vim.diagnostic.severity.WARN] or 0
  if e > 0 or w > 0 then
    parts[#parts + 1] = "%#StatusLineDiag#"
    if e > 0 then
      parts[#parts + 1] = "%#StatusLineError# E:" .. e
    end
    if w > 0 then
      parts[#parts + 1] = "%#StatusLineWarn# W:" .. w
    end
  end

  -- Cursor position.
  parts[#parts + 1] = "%=" .. "%#" .. info_hl .. "# %-14.(%l,%c%V%)"

  return table.concat(parts, "")
end

opt.statusline = "%!v:lua.nvim_statusline()"