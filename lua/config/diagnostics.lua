-- Diagnostic configuration using native vim.diagnostic.

local M = {}

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

function M.toggle_virtual_text()
  virtual_text_enabled = not virtual_text_enabled
  vim.diagnostic.config({ virtual_text = virtual_text_enabled and { spacing = 2, prefix = "●" } or false })
  vim.notify("Diagnostic virtual text: " .. (virtual_text_enabled and "on" or "off"))
end

return M