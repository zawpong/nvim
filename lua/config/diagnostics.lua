-- Diagnostic configuration using native vim.diagnostic.

local M = {}

local virtual_text = { spacing = 2, prefix = "●" }

local function apply()
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
    virtual_text = virtual_text,
    float = { border = "rounded", source = "if_many" },
    update_in_insert = false,
  })
end

apply()

---Toggle virtual-text diagnostics without touching the other settings.
function M.toggle_virtual_text()
  if virtual_text then
    virtual_text = false
  else
    virtual_text = { spacing = 2, prefix = "●" }
  end
  apply()
  vim.notify("Diagnostic virtual text: " .. (virtual_text and "on" or "off"))
end

---Jump to the next/previous diagnostic (count-aware); the 0.11+ jump API
---supersedes the deprecated goto_next/goto_prev pair.
---@param direction "next"|"prev"
function M.jump(direction)
  local count = vim.v.count1
  if direction == "prev" then
    count = -count
  end
  vim.diagnostic.jump({ count = count, float = true })
end

return M
