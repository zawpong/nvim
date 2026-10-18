-- Minimal statusline with diagnostic counts.

local opt = vim.opt

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