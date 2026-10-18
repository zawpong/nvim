-- Native multicursor support (Neovim 0.13+).
--
-- This module NEVER emulates multicursor in Lua. Multicursor editing is a
-- native editor feature: Q, zq{motion}, zqn, {Visual}Q, q=, gQ, ]C, [C and
-- CTRL-L work as shipped in 0.13 and are not remapped here.
--
-- On 0.12 stable (where the features do not exist) this module only documents
-- the situation; nothing is faked.
--
-- `:MulticursorInfo` reports the live state (requires 0.13+ for anything but
-- the version note).

local u = require("config.utils")

local M = {}

local function state_line()
  if not u.has_native_multicursor() then
    return nil
  end
  local ok, active = pcall(function()
    if vim.multicursor and vim.multicursor.active then
      return vim.multicursor.active(0)
    end
    local mc = require("vim._core.mcursor")
    return mc.active(0)
  end)
  if ok and type(active) == "number" then
    return active
  end
  return nil -- 0.13 nightly internals shifted; report without a count
end

function M.info()
  local lines = {}
  if u.has_native_multicursor() then
    local n = state_line()
    if n then
      lines[#lines + 1] = ("native multicursor active with %d cursor(s)"):format(n)
    else
      lines[#lines + 1] = "native multicursor available (count unavailable in this build)"
    end
    lines[#lines + 1] = [[
keys (native, unmapped):
  Q          toggle a cursor at the cursor position (count adds/removes)
  zq{motion} place a cursor at each motion target (zqn: each match)
  {Visual}Q  a cursor per selected line
  q=         follow mode (replay keys at every cursor)
  gQ         restore the last cleared session
  ]C / [C    jump to next/previous cursor
  CTRL-L     clear all cursors
limitations:
  display uses the kitty multi-cursor protocol when the terminal supports it,
  else hl-MCursor extmark highlighting (see :checkhealth vim.health)]]
  else
    lines[#lines + 1] =
      [[native multicursor requires Neovim 0.13 or newer.
  * 0.13 is nightly-only at the time this configuration was written; the
    installed editor keeps its 0.12 defaults and nothing here emulates
    multicursor in Lua.
  * This config was deliberately NOT built on nightly APIs: install a 0.13
    nightly explicitly (`./install.sh --nightly`) once you accept the risk.]]
  end
  vim.notify(table.concat(lines, "\n"))
end

function M.setup()
  vim.api.nvim_create_user_command("MulticursorInfo", M.info, { desc = "Multicursor state and keys" })
end

M.state_line = state_line

return M
